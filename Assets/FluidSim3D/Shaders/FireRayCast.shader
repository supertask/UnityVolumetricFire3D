// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'


Shader "3DFluidSim/FireRayCast" 
{
	Properties
	{
		_FireGradient("FireGradient", 2D) = "red" {}
		_SmokeGradient("SmokeGradient", 2D) = "white" {}
		//_SmokeColor("SmokeGradient", Color) = (0,0,0,1)
		//_SmokeAbsorption("SmokeAbsorbtion", float) = 60.0
		//_FireAbsorption("FireAbsorbtion", float) = 40.0
	}
	SubShader 
	{
		Tags { "Queue" = "Transparent" }
	
    	Pass 
    	{
    	
    		Cull front
    		Blend SrcAlpha OneMinusSrcAlpha

			CGPROGRAM
			#include "UnityCG.cginc"
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
			#define RAY_STEPS_TO_LIGHT 16

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
			sampler2D _FireGradient;
			sampler2D _SmokeGradient;
			float _SmokeAbsorption, _FireAbsorption; //absorption = 吸収
			uniform float3 _BoundingPosition, _BoundingScale, _Size;
			StructuredBuffer<float> _Density, _Reaction;
			float3 boundsMax;
			float3 boundsMin;

			//Textures
            Texture2D<float4> BlueNoise;
			SamplerState samplerBlueNoise;
			
			//Unity provided
			sampler2D _CameraDepthTexture;

			// Marching settings
			float _RayOffsetStrength;

			// Shape settings
			float4 _PhaseParams;

			// Light settings
            float _LightAbsorptionTowardSun;
            float _LightAbsorptionThroughCloud;
			float _DarknessThreshold;
            float4 _LightColor0;
			float4 _SkyColor;
			
			// Henyey-Greenstein
            float hg(float a, float g) {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(1+g2-2*g*(a), 1.5));
            }

            float phase(float a) {
                float blend = .5;
                float hgBlend = hg(a,_PhaseParams.x) * (1-blend) + hg(a,-_PhaseParams.y) * blend;
                return _PhaseParams.z + hgBlend*_PhaseParams.w;
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
            float lightmarch(float3 rayWorldPosFromCamera, BoundingBox boundingBox) {
                //float3 dirToLight = _WorldSpaceLightPos0.xyz;
                //float dstInsideBox = rayBoxDst(boundsMin, boundsMax, rayWorldPosFromCamera, 1/dirToLight).y;
				Ray rayTowardsLight; //Ray from cloud particle position to light position.
				rayTowardsLight.origin = rayWorldPosFromCamera;
				rayTowardsLight.dir = _WorldSpaceLightPos0.xyz;
				float dstInsideBox = rayBoundsDistance(rayTowardsLight, boundingBox).y; //Confirmed!!!
                
                float stepSize = dstInsideBox/RAY_STEPS_TO_LIGHT;
                float totalDensity = 0;

				float3 lightRayPos = rayTowardsLight.origin;
                for (int step = 0; step < RAY_STEPS_TO_LIGHT; step ++) {
                    lightRayPos += rayTowardsLight.dir * stepSize;

					float3 rayPosOnUVW = (lightRayPos - _BoundingPosition + 0.5*_BoundingScale)/_BoundingScale;
					float density = SampleBilinear(_Density, rayPosOnUVW, _Size);
                    totalDensity += max(0, density * stepSize);
                }
				return totalDensity > 0 ? 1 : 0;

                //float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                //return _DarknessThreshold + transmittance * (1-_DarknessThreshold);
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
    			
    			//convert to texture space
				/*
    			entryPoint -= _BoundingPosition;
    			exitPoint -= _BoundingPosition;
   				entryPoint = (entryPoint + 0.5*_BoundingScale)/_BoundingScale;
   				exitPoint = (exitPoint + 0.5*_BoundingScale)/_BoundingScale;
				   */
				float randomOffset = BlueNoise.SampleLevel(samplerBlueNoise, squareUV(screenUV * 30), 0);
				randomOffset *= _RayOffsetStrength;
				//return float4(randomOffset, 0, 0, 1);

				// Phase function makes clouds brighter around sun
                float cosAngle = dot(ray.dir, _WorldSpaceLightPos0.xyz);
                float phaseVal = phase(cosAngle);
  
				float3 rayPos = entryPoint;
				float stepSize = distance(exitPoint, entryPoint)/float(RAY_STEPS_TO_FLUID); //This is problem of while loop
				//float stepSize = 0.05;
			    //float3 ds = normalize(exitPoint-entryPoint) * stepSize;
				//float dstLimit = min(depth-dstToBox, dstInsideBox);
				//dstLimit is problem!!!

				float lightEnergy = 0;
			    float fireTransmittance = 1.0, smokeTransmittance = 1.0;
				float dstLimit = dstInsideBox - dstToBox;
				float dstTravelled = 0.0;
				//float dstTravelled = lerp(0, dstLimit, randomOffset);
			
				return float4(lightmarch(IN.worldPos, boundingBox), 0,0,1);

				while (dstTravelled < dstLimit) {
   				//for(int i=0; i < RAY_STEPS_TO_FLUID; i++, rayPos += ds) {
   				//for(int i=0; i < RAY_STEPS_TO_FLUID; i++, dstTravelled += stepSize) {
					rayPos = entryPoint + ray.dir * dstTravelled;

					//Convert World position to UVW position
					float3 rayPosOnUVW = (rayPos - _BoundingPosition + 0.5*_BoundingScale)/_BoundingScale;
					//rayPosOnUVW = (rayPosOnUVW - _BoundingPosition) * _BoundingScale + float3(0.5, 0.5, 0.5);

   					float density = SampleBilinear(_Density, rayPosOnUVW, _Size);
   					float reaction = SampleBilinear(_Reaction, rayPosOnUVW, _Size);
        			//smokeTransmittance *= 1.0-saturate(density*stepSize*_SmokeAbsorption);
        			//fireTransmittance *= 1.0-saturate(reaction*stepSize*_FireAbsorption);

					if (density > 0) {
						float lightTransmittance = lightmarch(rayPos, boundingBox);
                        lightEnergy += density * stepSize * smokeTransmittance * lightTransmittance * phaseVal; //Not confirmed.....
                        smokeTransmittance *= exp(-density * stepSize * _LightAbsorptionThroughCloud); //Confirmed!!
						//if not very dense, most light makes it through
						//if very dense, not much light makes it through

						if(smokeTransmittance <= 0.01) break;
					}

        			//if(fireTransmittance <= 0.01 && smokeTransmittance <= 0.01) break;

					dstTravelled += stepSize;
			    }
			    
			    //float4 smoke = tex2D(_SmokeGradient, float2(smokeTransmittance,0)) * (1.0-smokeTransmittance);
			    //float4 fire = tex2D(_FireGradient, float2(fireTransmittance,0)) * (1.0-fireTransmittance);
				//return fire + smoke;

				//float4 smoke = _SkyColor * smokeTransmittance + lightEnergy * _LightColor0; //little bit blue sky , bit light color
				//return smoke;
				return float4(_WorldSpaceLightPos0.xyz, 1);
				//float4 smoke = tex2D(_SmokeGradient, float2(smokeTransmittance,0)) * (1.0 - smokeTransmittance);
				//float4 smoke = lightEnergy * _LightColor0;
				//return smoke;

			}




			ENDCG

    	}
	}
}





















