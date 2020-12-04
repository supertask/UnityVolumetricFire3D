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
			};

			v2f vert(appdata_base v)
			{
    			v2f OUT;
    			OUT.pos = UnityObjectToClipPos(v.vertex);
    			OUT.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
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
			// rayPosFromCamera:
			//     ray marching position from eye to clouds
			//     rayPosFromCamera near equeals a cloud particle position
			//
            float lightmarch(float3 rayPosFromCamera, BoundingBox boundingBox) {
                float3 dirToLight = _WorldSpaceLightPos0.xyz;
                //float dstInsideBox = rayBoxDst(boundsMin, boundsMax, rayPosFromCamera, 1/dirToLight).y;
				Ray rayTowardsLight; //Ray from cloud particle position to light position.
				rayTowardsLight.origin = rayPosFromCamera;
				rayTowardsLight.dir = dirToLight;
				float2 distanceIntersectedToFarBounds = rayBoundsDistance(rayTowardsLight, boundingBox).y; //Confirmed!!!
                
                float stepSize = distanceIntersectedToFarBounds/RAY_STEPS_TO_LIGHT;
                float totalDensity = 0;

				float rayPosForLight = rayPosFromCamera;
                for (int step = 0; step < RAY_STEPS_TO_LIGHT; step ++) {
                    rayPosForLight += rayTowardsLight.dir * stepSize;
					//float density = sampleDensity(rayPosForLight, boundingBox);
					float density = SampleBilinear(_Density, rayPosForLight, _Size);
                    totalDensity += max(0, density * stepSize);
                }

                float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                return _DarknessThreshold + transmittance * (1-_DarknessThreshold);
            }

			
			float4 frag(v2f IN) : COLOR
			{
				//
				// IN.worldPos means a world position on each pixel of the bounding box 
				//
				Ray ray;
				ray.origin = _WorldSpaceCameraPos;
				ray.dir = normalize(IN.worldPos - _WorldSpaceCameraPos);
				
				BoundingBox boundingBox;
				boundingBox.Min = float3(-0.5,-0.5,-0.5)*_BoundingScale + _BoundingPosition;
				boundingBox.Max = float3(0.5,0.5,0.5)*_BoundingScale + _BoundingPosition;

				//figure out where ray from eye hit front of cube
				float tnear, tfar;
				intersectBox(ray, boundingBox, tnear, tfar);
				
				//if eye is in cube then start ray at eye
				if (tnear < 0.0) tnear = 0.0;

				float3 rayStart = ray.origin + ray.dir * tnear; //world position of ray start point
    			float3 rayStop = ray.origin + ray.dir * tfar;
    			
    			//convert to texture space
    			rayStart -= _BoundingPosition;
    			rayStop -= _BoundingPosition;
   				rayStart = (rayStart + 0.5*_BoundingScale)/_BoundingScale;
   				rayStop = (rayStop + 0.5*_BoundingScale)/_BoundingScale;
  
				float3 rayPos = rayStart;
				float dist = distance(rayStop, rayStart);
				float stepSize = dist/float(RAY_STEPS_TO_FLUID);
			    float3 ds = normalize(rayStop-rayStart) * stepSize;
	

				float lightEnergy = 0;
			    float smokeTransmittance = 1.0;
   				for(int i=0; i < RAY_STEPS_TO_FLUID; i++, rayPos += ds) 
   				{
   					float density = SampleBilinear(_Density, rayPos, _Size);
   				 	
					if (density > 0) {
						float lightTransmittance = lightmarch(rayPos, boundingBox);
                        //lightEnergy += density * smokeTransmittance * lightTransmittance; //Not confirmed.....
                        lightEnergy += density * smokeTransmittance * lightTransmittance; //Not confirmed.....
                        smokeTransmittance *= exp(-density * _LightAbsorptionThroughCloud); //Confirmed!!
						//if not very dense, most light makes it through
						//if very dense, not much light makes it through

						if(smokeTransmittance <= 0.01) break;
					}
			    }

				//smokeTransmittance = 0;
				//lightEnergy = 1;
				float3 smokeCol = float3(0.9,0.9,1) * smokeTransmittance + lightEnergy * _LightColor0; //little bit blue sky , bit light color

				return float4(smokeCol, 1.0);

				//return float4(lightEnergy,0,0,1);
				//return float4(smokeTransmittance,0,0,1);


				///return float4(lightmarch(IN.worldPos, boundingBox), 0,0, 1);
			}
			
			ENDCG

    	}
	}
}





















