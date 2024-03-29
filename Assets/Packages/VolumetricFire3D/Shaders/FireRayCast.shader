// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'


Shader "3DFluidSim/FireRayCast" 
{
	Properties
	{
		_FireGradient("FireGradient", 2D) = "red" {}
		_SmokeGradient("SmokeGradient", 2D) = "white" {}

		//_SmokeColor("SmokeColor", Color) = (1, 1, 1, 1)
		//_FireColor("FireColor", Color) = (1, 0.594, 0.282, 1)
		
		//_SmokeAbsorption("SmokeAbsorbtion", float) = 60.0
		//_FireAbsorption("FireAbsorbtion", float) = 40.0
	}
	SubShader 
	{
		Tags {
			"Queue" = "Transparent"
			"RenderType" = "Transparent"
		}

        // No culling or depth
		Cull Off ZWrite Off ZTest Always

		//col.xyz * col.w + backCol.xyz * (1 - col.w)
		Blend SrcAlpha OneMinusSrcAlpha
		
	
		GrabPass{ }
    	Pass 
    	{
    	
    		//Cull front
    		//Blend SrcAlpha OneMinusSrcAlpha

			CGPROGRAM
			#include "UnityCG.cginc"
			#include "Assets/Packages/VolumetricFire3D/Shaders/rgb_to_cmyk.hlsl"
			#pragma target 5.0
			#pragma vertex vert
			#pragma fragment frag
			
		
			struct v2f 
			{
    			float4 pos : SV_POSITION;
    			float3 worldPos : TEXCOORD0;
				float3 screenPos : TEXCOORD1;
				float3 viewVector : TEXCOORD2;
			};

			v2f vert(appdata_base v)
			{
    			v2f OUT;
    			OUT.pos = UnityObjectToClipPos(v.vertex);
    			OUT.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

				//https://gamedev.stackexchange.com/questions/129139/how-do-i-calculate-uv-space-from-world-space-in-the-fragment-shader
				OUT.screenPos = OUT.pos.xyw;
				// Correct flip when rendering with a flipped projection matrix.
				// (I've observed this differing between the Unity scene & game views)
				OUT.screenPos.y *= _ProjectionParams.x; //For multi-platform like VR

				// Ref. Clouds
				// Camera space matches OpenGL convention where cam forward is -z. In unity forward is positive z.
                // (https://docs.unity3d.com/ScriptReference/Camera-cameraToWorldMatrix.html)
				float2 screenUV = (OUT.screenPos.xy / OUT.screenPos.z) * 0.5f + 0.5f;
                float3 viewVector = mul(unity_CameraInvProjection, float4(screenUV * 2 - 1, 0, -1));
                OUT.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));

				//memo
				//https://light11.hatenadiary.com/entry/2018/06/13/235543

    			return OUT;
			}
			
			#define RAY_STEPS_TO_FLUID 64
			#define RAY_STEPS_TO_LIGHT 8

			struct Ray {
				float3 origin;
				float3 dir;
			};
			
			struct BoundingBox {
			    float3 Min;
			    float3 Max;
			};

			//
			// Fire & smoke settings
			//
			//sampler2D _FireGradient;
			//sampler2D _SmokeGradient;

            Texture2D<float4> FireGradient;
            Texture2D<float4> SmokeGradient;
			SamplerState samplerFireGradient;
			SamplerState samplerSmokeGradient;

			float _SmokeAbsorption, _FireAbsorption; //absorption = 吸収
			uniform float3 _BoundingPosition, _BoundingScale, _Size;
			StructuredBuffer<float> _Density, _Reaction, _Temperature;
			float3 boundsMax;
			float3 boundsMin;
			//float4 _SmokeColor;
			//float4 _FireColor;
			float _FireIntensity;

			//Textures
			uniform sampler2D _GrabTexture;
			
			//Unity provided
			sampler2D _CameraDepthTexture;

			// Marching settings
			float _RayOffsetStrength;

			// Shape settings
			float4 _PhaseParams;
			float _DensityOffset;
			float _ReactionOffset;

			// Light settings
            float _LightAbsorptionTowardSun;
            float _LightAbsorptionThroughCloud;
			float _DarknessThreshold;
            float4 _LightColor0;
			float4 _SkyColor;

			float2 _FireTemperatureRange;
			float2 _SmokeDensityRange;
			
			// Henyey-Greenstein(散乱位相関数モデル)
			// https://www.astro.umd.edu/~jph/HG_note.pdf
            float hg(float a, float g) {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(1+g2-2*g*(a), 1.5));
            }

			//https://www.cps-jp.org/~mosir/pub/2013/2013-11-28/01_satou/pub-web/20131128_satou_01.pdf 
            float phase(float a) {
                float blend = .5;
                float hgBlend = hg(a,_PhaseParams.x) * (1-blend) + hg(a,-_PhaseParams.y) * blend;
                return _PhaseParams.z + hgBlend*_PhaseParams.w;
            }

			float remap(float v, float minOld, float maxOld, float minNew, float maxNew) {
                return minNew + (v-minOld) * (maxNew - minNew) / (maxOld-minOld);
            }

			float2 squareUV(float2 uv) {
                float width = _ScreenParams.x;
                float height =_ScreenParams.y;
                //float minDim = min(width, height);
                float scale = 1000;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2 (x/scale, y/scale);
            }

			float3 blendLikePaint(float3 rbgL, float3 rgbR)	 {
				return CMYKtoRGB(RGBtoCMYK(rbgL) + RGBtoCMYK(rgbR));
			}

			float2 rayBoundsDistance(Ray ray, BoundingBox boundingBox)
			{
			    float3 inverseRayDir = 1.0 / ray.dir;
			    float3 tbot = inverseRayDir * (boundingBox.Min-ray.origin);
			    float3 ttop = inverseRayDir * (boundingBox.Max-ray.origin);
			    float3 tmin = min(ttop, tbot);
			    float3 tmax = max(ttop, tbot);
			    float2 t = max(tmin.xx, tmin.yz);
			    float distanceIntersectedToNearBounds = max(t.x, t.y);
			    t = min(tmax.xx, tmax.yz);
			    float distanceIntersectedToFarBounds = min(t.x, t.y);

                return float2(distanceIntersectedToNearBounds, distanceIntersectedToFarBounds);
			}
			
			//find intersection points of a ray with a box
			bool intersectBox(Ray ray, BoundingBox boundingBox, out float t0, out float t1)
			{
			    float3 invR = 1.0 / ray.dir;
			    float3 tbot = invR * (boundingBox.Min-ray.origin);
			    float3 ttop = invR * (boundingBox.Max-ray.origin);
			    float3 tmin = min(ttop, tbot);
			    float3 tmax = max(ttop, tbot);
			    float2 t = max(tmin.xx, tmin.yz);
			    t0 = max(t.x, t.y);
			    t = min(tmax.xx, tmax.yz);
			    t1 = min(t.x, t.y);
			    return t0 <= t1;
			}
			
			float SampleBilinear(StructuredBuffer<float> buffer, float3 uvw, float3 size)
			{
				uvw = saturate(uvw);
				uvw = uvw * (size-1.0);
			
				int x = uvw.x;
				int y = uvw.y;
				int z = uvw.z;
				
				int X = size.x;
				int XY = size.x*size.y;
				
				float fx = uvw.x-x;
				float fy = uvw.y-y;
				float fz = uvw.z-z;
				
				int xp1 = min(_Size.x-1, x+1);
				int yp1 = min(_Size.y-1, y+1);
				int zp1 = min(_Size.z-1, z+1);
				
				float x0 = buffer[x+y*X+z*XY] * (1.0f-fx) + buffer[xp1+y*X+z*XY] * fx;
				float x1 = buffer[x+y*X+zp1*XY] * (1.0f-fx) + buffer[xp1+y*X+zp1*XY] * fx;
				
				float x2 = buffer[x+yp1*X+z*XY] * (1.0f-fx) + buffer[xp1+yp1*X+z*XY] * fx;
				float x3 = buffer[x+yp1*X+zp1*XY] * (1.0f-fx) + buffer[xp1+yp1*X+zp1*XY] * fx;
				
				float z0 = x0 * (1.0f-fz) + x1 * fz;
				float z1 = x2 * (1.0f-fz) + x3 * fz;
				
				return z0 * (1.0f-fy) + z1 * fy;
				
			}

			// Convert World position to UVW position
            float3 convertFromWorldPosToUVW(float3 rayWorldPos) {
				float3 rayUVWPos = (rayWorldPos - _BoundingPosition + 0.5*_BoundingScale)/_BoundingScale;
				return rayUVWPos;
			}

			/*
            float sampleDensity(float3 rayWorldPos, BoundingBox boundingBox) {
				float3 rayUVWPos = convertFromWorldPosToUVW(rayWorldPos);
				float fluidSimulatedDensity = SampleBilinear(_Density, rayUVWPos, _Size);
                float density = _DensityOffset * .1 * fluidSimulatedDensity;
				return density;
			}*/

			float samplePhysicalQuantity(StructuredBuffer<float> buffer,
					float3 rayWorldPos, BoundingBox boundingBox, float physicalQuantityOffset) {
				float3 rayUVWPos = convertFromWorldPosToUVW(rayWorldPos);
				float sampledPhysicalQuantity = SampleBilinear(buffer, rayUVWPos, _Size);
                float physicalQuantity = physicalQuantityOffset * sampledPhysicalQuantity;
				return physicalQuantity;
			}

			// Calculate proportion of light that reaches the given point from the lightsource
			//
			// rayWorldPosFromCamera: expects WORLD POSITION
			//     ray marching position from eye to clouds
			//     rayWorldPosFromCamera near equeals a cloud particle position
			//
			//
			// Calculate texture sample positions
            //    float3 size = boundsMax - boundsMin;
            //    float3 boundsCentre = (boundsMin+boundsMax) * .5;
            //    float3 uvw = (size * .5 + rayPos) * baseScale * scale;
			//
			/*
            float lightmarchBackup(float3 rayWorldPosFromCamera, BoundingBox boundingBox) {
				Ray rayTowardsLight; //Ray from cloud particle position to light position.
				rayTowardsLight.origin = rayWorldPosFromCamera;
				rayTowardsLight.dir = _WorldSpaceLightPos0.xyz;
				float dstInsideBox = rayBoundsDistance(rayTowardsLight, boundingBox).y; //Confirmed!!!
                
                float stepSize = dstInsideBox/RAY_STEPS_TO_LIGHT;
                float totalDensity = 0;

				float3 lightRayPos = rayTowardsLight.origin;
                for (int step = 0; step < RAY_STEPS_TO_LIGHT; step ++) {
                    lightRayPos += rayTowardsLight.dir * stepSize;
					float density = sampleDensity(lightRayPos, boundingBox);
                    totalDensity += max(0, density * stepSize);
                }
                float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                return _DarknessThreshold + transmittance * (1-_DarknessThreshold);
            }
			*/

			// 
			// Ref. Sebastian Lague, Clouds, https://github.com/SebLague/Clouds
			float lightmarch(StructuredBuffer<float> buffer, float3 rayWorldPosFromCamera,
					BoundingBox boundingBox, float physicalQuantityOffset) {
				Ray rayTowardsLight; //Ray from cloud particle position to light position.
				rayTowardsLight.origin = rayWorldPosFromCamera;
				rayTowardsLight.dir = _WorldSpaceLightPos0.xyz;
				float dstInsideBox = rayBoundsDistance(rayTowardsLight, boundingBox).y; //Confirmed!!!
                
                float stepSize = dstInsideBox/RAY_STEPS_TO_LIGHT;
                float totalPhysicalQuantity = 0;

				float3 lightRayPos = rayTowardsLight.origin;
                for (int step = 0; step < RAY_STEPS_TO_LIGHT; step ++) {
                    lightRayPos += rayTowardsLight.dir * stepSize;
					float physicalQuantity = samplePhysicalQuantity(buffer, lightRayPos, boundingBox, physicalQuantityOffset);
                    totalPhysicalQuantity += max(0, physicalQuantity * stepSize);
                }
                float transmittance = exp(-totalPhysicalQuantity * _LightAbsorptionTowardSun);
                return _DarknessThreshold + transmittance * (1-_DarknessThreshold);
			}
			


			float4 frag(v2f IN) : COLOR
			{
				float2 screenUV = (IN.screenPos.xy / IN.screenPos.z) * 0.5f + 0.5f;
				float viewLength = length(IN.viewVector);

				Ray ray;
				ray.origin = _WorldSpaceCameraPos;
				ray.dir = normalize(IN.worldPos - _WorldSpaceCameraPos);
				
				BoundingBox boundingBox;
				boundingBox.Min = float3(-0.5,-0.5,-0.5)*_BoundingScale + _BoundingPosition;
				boundingBox.Max = float3(0.5,0.5,0.5)*_BoundingScale + _BoundingPosition;

                //float nonlin_depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, screenUV);
				//float depth = LinearEyeDepth(nonlin_depth) * viewLength; //far>=1, near=0

				//figure out where ray from eye hit front of cube
                float2 rayToContainerInfo = rayBoundsDistance(ray, boundingBox);
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;

				//if eye is in cube then start ray at eye
				if (dstToBox < 0.0) dstToBox = 0.0;

				float3 entryPoint = ray.origin + ray.dir * dstToBox;
    			float3 exitPoint = ray.origin + ray.dir * dstInsideBox;

				// Phase function makes clouds brighter around sun
                float cosAngle = dot(ray.dir, _WorldSpaceLightPos0.xyz);
                float phaseVal = phase(cosAngle);
  
				float3 rayPos = entryPoint;
				float stepSize = distance(exitPoint, entryPoint)/float(RAY_STEPS_TO_FLUID); //This is problem of while loop
				//float stepSize = 0.05;
			    //float3 ds = normalize(exitPoint-entryPoint) * stepSize;
				//float dstLimit = min(depth-dstToBox, dstInsideBox);

				float lightEnergyForSmoke = 0;
				float lightEnergyForFire = 0;
			    float fireTransmittance = 1.0, smokeTransmittance = 1.0;
				float dstLimit = dstInsideBox - dstToBox;
				float dstTravelled = 0.0;
				//float dstTravelled = randomOffset;

				float normalizedFireTemperature = 1.0;
				float normalizedSmokeTemperature = 1.0;
			
				//while (dstTravelled < dstLimit) {
   				//for(int i=0; i < RAY_STEPS_TO_FLUID; i++, rayPos += ds) {
   				for(int i=0; i < RAY_STEPS_TO_FLUID; i++, dstTravelled += stepSize) {
					rayPos = entryPoint + ray.dir * dstTravelled;

					float density = samplePhysicalQuantity(_Density, rayPos, boundingBox, _DensityOffset);
					float reaction = samplePhysicalQuantity(_Reaction, rayPos, boundingBox, _ReactionOffset);

					if (density > 0) {
						float lightTransmittance = lightmarch(_Density, rayPos, boundingBox, _DensityOffset);
                        lightEnergyForSmoke += density * stepSize * smokeTransmittance * lightTransmittance * phaseVal; //Not confirmed.....
                        smokeTransmittance *= exp(-density * stepSize * _LightAbsorptionThroughCloud); //Confirmed!!
						//if not very dense, most light makes it through
						//if very dense, not much light makes it through
						normalizedSmokeTemperature *= 1.0-saturate(density * stepSize * 0.5);

						if (smokeTransmittance <= 0.01) break;
						if (normalizedSmokeTemperature < 0.01) break;
					} 
					if (reaction > 0) {
						float lightFireTransmittance = lightmarch(_Reaction, rayPos, boundingBox, _DensityOffset);
						lightEnergyForFire += reaction * stepSize * fireTransmittance * lightFireTransmittance * phaseVal;
						fireTransmittance *= exp(-reaction * stepSize * _LightAbsorptionThroughCloud );

						normalizedFireTemperature *= 1.0-saturate(reaction * stepSize * 0.5);

						if (fireTransmittance <= 0.01) break;
						if (normalizedFireTemperature < 0.01) break;
					}

			    }

				//float4 fireCol = _FireColor;
				float4 fireCol = FireGradient.SampleLevel(samplerFireGradient, float2(normalizedFireTemperature, 0), 0);
				fireCol = fireCol * _FireIntensity * lightEnergyForFire * (1 - smokeTransmittance);

				float4 smoke = SmokeGradient.SampleLevel(samplerSmokeGradient, float2(normalizedSmokeTemperature, 0), 0);
				float4 smokeCol = float4(lightEnergyForSmoke * blendLikePaint(_LightColor0.rgb, smoke.rgb), 1.0 - smokeTransmittance);
				float4 sceneColor = tex2D(_GrabTexture, screenUV);

				return lerp(smokeCol, sceneColor, smokeTransmittance) + fireCol;
			}




			ENDCG

    	}
	}
}





















