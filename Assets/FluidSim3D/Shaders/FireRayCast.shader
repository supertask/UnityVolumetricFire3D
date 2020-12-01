// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'


Shader "3DFluidSim/FireRayCast" 
{
	Properties
	{
		_FireGradient("FireGradient", 2D) = "red" {}
		_SmokeGradient("SmokeGradient", 2D) = "yellow" {}
	}
	SubShader 
	{
		// No culling or depth
        Cull Off ZWrite Off ZTest Always

		//Tags { "Queue" = "Transparent" }
	
    	Pass 
    	{
    		//Cull front
    		//Blend SrcAlpha OneMinusSrcAlpha

			CGPROGRAM
			#include "UnityCG.cginc"
			#pragma target 5.0
			#pragma vertex vert
			#pragma fragment frag
	
			// vertex input: position, UV
            struct appdata {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };
		
			struct v2f {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 viewVector : TEXCOORD1;
            };

			v2f vert(appdata v)
			{
    			v2f output;
    			output.pos = UnityObjectToClipPos(v.vertex);
    			//output.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				output.uv = v.uv;

                // Camera space matches OpenGL convention where cam forward is -z. In unity forward is positive z.
                // (https://docs.unity3d.com/ScriptReference/Camera-cameraToWorldMatrix.html)
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                output.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));

    			return output;
			}		


			#define NUM_SAMPLES 64
			#define RAY_STEPS_FOR_LIGHT 8

			struct Ray {
				float3 origin;
				float3 dir;
			};
			
			struct Bounds {
			    float3 Min;
			    float3 Max;
			};

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

			//
			// Fire & smoke settings
			//
			sampler2D _FireGradient;
			sampler2D _SmokeGradient;
			float _SmokeAbsorption, _FireAbsorption; //absorption = 吸収
			uniform float3 _Translate, _BoundsScale, _VoxelSize;
			StructuredBuffer<float> _Density, _Reaction;
			Bounds bounds;
			float3 boundsMax;
			float3 boundsMin;



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

			float2 rayBoundsDistance(Ray ray, Bounds bounds)
			{
			    float3 inverseRayDir = 1.0 / ray.dir;
			    float3 tbot = inverseRayDir * (bounds.Min-ray.origin);
			    float3 ttop = inverseRayDir * (bounds.Max-ray.origin);
			    float3 tmin = min(ttop, tbot);
			    float3 tmax = max(ttop, tbot);
			    float2 t = max(tmin.xx, tmin.yz);
			    float distanceIntersectedToNearBounds = max(t.x, t.y);
			    t = min(tmax.xx, tmax.yz);
			    float distanceIntersectedToFarBounds = min(t.x, t.y);

                return float2(distanceIntersectedToNearBounds, distanceIntersectedToFarBounds);
			}
			
			float sampleBilinear(StructuredBuffer<float> buffer, float3 uvw, float3 size)
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
				
				int xp1 = min(_VoxelSize.x-1, x+1);
				int yp1 = min(_VoxelSize.y-1, y+1);
				int zp1 = min(_VoxelSize.z-1, z+1);
				
				float x0 = buffer[x+y*X+z*XY] * (1.0f-fx) + buffer[xp1+y*X+z*XY] * fx;
				float x1 = buffer[x+y*X+zp1*XY] * (1.0f-fx) + buffer[xp1+y*X+zp1*XY] * fx;
				
				float x2 = buffer[x+yp1*X+z*XY] * (1.0f-fx) + buffer[xp1+yp1*X+z*XY] * fx;
				float x3 = buffer[x+yp1*X+zp1*XY] * (1.0f-fx) + buffer[xp1+yp1*X+zp1*XY] * fx;
				
				float z0 = x0 * (1.0f-fz) + x1 * fz;
				float z1 = x2 * (1.0f-fz) + x3 * fz;
				
				return z0 * (1.0f-fy) + z1 * fy;
				
			}

			float sampleDensity(float3 rayPos, Bounds bounds) {
				const float baseScale = 1/1000.0;
				float3 size = bounds.Max - bounds.Min;
				float3 uvw = (size * .5 + rayPos) * baseScale; //* scale??
				return sampleBilinear(_Density, uvw, _VoxelSize);
			}

			// Calculate proportion of light that reaches the given point from the lightsource
			//
			// rayPosFromCamera:
			//     ray marching position from eye to clouds
			//     rayPosFromCamera near equeals a cloud particle position
			//
            float lightmarch(float3 rayPosFromCamera, Bounds bounds) {
                float3 dirToLight = _WorldSpaceLightPos0.xyz;
                //float dstInsideBox = rayBoxDst(boundsMin, boundsMax, rayPosFromCamera, 1/dirToLight).y;
				Ray rayTowardsLight; //Ray from cloud particle position to light position.
				rayTowardsLight.origin = rayPosFromCamera;
				rayTowardsLight.dir = dirToLight;
				float2 distanceIntersectedToFarBounds = rayBoundsDistance(rayTowardsLight, bounds).y;
                
                float stepSize = distanceIntersectedToFarBounds/RAY_STEPS_FOR_LIGHT;
                float totalDensity = 0;

				float rayPosForLight = rayTowardsLight.origin;
                for (int step = 0; step < RAY_STEPS_FOR_LIGHT; step ++) {
                    rayPosForLight += rayTowardsLight.dir * stepSize;
					float density = sampleDensity(rayPosForLight, bounds);
                    totalDensity += max(0, density * stepSize);
                }

                float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                return _DarknessThreshold + transmittance * (1-_DarknessThreshold);
            }

/*
			float4 frag(v2f input) : COLOR
			{
				Ray ray;
				ray.origin = _WorldSpaceCameraPos;
				ray.dir = normalize(input.viewVector); //r.dir = normalize(input.worldPos-pos);
				float4 col = float4(1.0, 0.0, 0.0, 1.0);

				float nonLinearDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, input.uv);
				float depth = LinearEyeDepth(nonLinearDepth) * length(input.viewVector);

				Bounds bounds;
				bounds.Min = float3(-0.5,-0.5,-0.5)*_BoundsScale + _Translate;
				bounds.Max = float3(0.5,0.5,0.5)*_BoundsScale + _Translate;

                float2 rayToContainerInfo = rayBoxDst(ray, bounds);
                float dstToBox = rayToContainerInfo.x; //distance beteen camera pos(ray.origin) and box  x >= 1.0
                float dstInsideBox = rayToContainerInfo.y; //x <= 0.0

				float dstTravelled = 0.0;
				float stepSize = dstInsideBox / NUM_SAMPLES;
				float dstLimit = min(depth - dstToBox, dstInsideBox);

				float totalDensity = 0.0;
				while (dstTravelled < dstLimit) {
					float rayPos = ray.origin + ray.dir * (dstToBox + dstTravelled);
					totalDensity += SampleBilinear(_Density, rayPos, _VoxelSize) * stepSize;

				}



				bool rayHitBox = dstInsideBox > 0.0; // && dstToBox < depth;
				if (!rayHitBox) {
					col = float4(dstInsideBox, 0.0, 0.0, 1.0);

					//col = float4(dstToBox, 0.0, 0.0, 1.0);
				}
				return col;
			}
*/

			
			float4 frag(v2f input) : COLOR
			{
				//return float4(input.uv, 0, 1);
				//return float4(_ScreenParams.x, _ScreenParams.y, 0, 1);
				
				bounds.Max = boundsMax;
				bounds.Min = boundsMin;

				float viewLength = length(input.viewVector);
				Ray rayFromCamera;
				rayFromCamera.origin = _WorldSpaceCameraPos;
				//rayFromCamera.dir = normalize(input.worldPos - _WorldSpaceCameraPos);
				rayFromCamera.dir = input.viewVector / viewLength;
				
                // Depth and cloud container intersection info:
                float nonlin_depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, input.uv);
                float depth = LinearEyeDepth(nonlin_depth) * viewLength;
				return float4(depth, 0, 0, 1); //?????

				//figure out where ray from eye hit front of cube
                float2 rayToContainerInfo = rayBoundsDistance(rayFromCamera, bounds);
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;

                // point of intersection with the cloud container
                float3 entryPoint = rayFromCamera.origin + rayFromCamera.dir * dstToBox;
				//return float4(entryPoint, 1); //?????

                // random starting offset (makes low-res results noisy rather than jagged/glitchy, which is nicer)
                float randomOffset = BlueNoise.SampleLevel(samplerBlueNoise, squareUV(input.uv*3), 0);
				//return float4(randomOffset, 0,0,1); //OK!!!!!

                randomOffset *= _RayOffsetStrength;
                
                // Phase function makes clouds brighter around sun
                float cosAngle = dot(rayFromCamera.dir, _WorldSpaceLightPos0.xyz);
                float phaseVal = phase(cosAngle);

                float dstTravelled = randomOffset;
                float dstLimit = min(depth-dstToBox, dstInsideBox);

				float lightEnergy = 0;
				const float stepSize = 11;
			    float fireTransmittance = 1.0;
				float smokeTransmittance = 1.0; //transmittance = alpha

				float3 currentRayPos = 0.0;
				float debugDensity = 1.0;
                while (dstTravelled < dstLimit) {
                    currentRayPos = entryPoint + rayFromCamera.dir * dstTravelled;
					float density = sampleDensity(currentRayPos, bounds);
					debugDensity = density;
                    
                    if (density > 0) {
                        float lightTransmittance = lightmarch(currentRayPos, bounds);
                        //float lightTransmittance = 1.0;
                        lightEnergy += density * stepSize * smokeTransmittance * lightTransmittance * phaseVal;
                        //lightEnergy += density;
                        smokeTransmittance *= exp(-density * stepSize * _LightAbsorptionThroughCloud);
                    
                        // Exit early if T is close to zero as further samples won't affect the result much
                        if (smokeTransmittance < 0.01) {
                            break;
                        }
                    }
                    dstTravelled += stepSize;
                }
				//float4 smokeCol = float4(smokeTransmittance, 0.0, 0.0, 1.0);
				//float4 smokeCol = float4(debugDensity, 0.0, 0.0, 1.0);


				/*
   				for(int i=0; i < NUM_SAMPLES; i++, rayPos += ds) 
   				{
   				 
   					float density = SampleBilinear(_Density, rayPos, _VoxelSize);
   					float R = SampleBilinear(_Reaction, rayPos, _VoxelSize);
   				 	
					//TODO(Tasuku): Fire simulation
        			//fireTransmittance *= 1.0-saturate(R*stepSize*_FireAbsorption);
        			//smokeTransmittance *= 1.0-saturate(density*stepSize*_SmokeAbsorption);
        			//if(fireTransmittance <= 0.01 && smokeTransmittance <= 0.01) break;

					if (density > 0) {
                        float lightTransmittance = lightmarch(rayPos, bounds);
						//lightEnergy += density * stepSize * smokeTransmittance * lightTransmittance * phaseVal;
						//stepSize looks like zero???
						//phaseVal looks like zero???
						lightEnergy += density * stepSize * smokeTransmittance * lightTransmittance;
                        smokeTransmittance *= exp(-density * stepSize * _LightAbsorptionThroughCloud);
						//smokeTransmittance *= 1.0-saturate(density*stepSize*_SmokeAbsorption);

                        // Exit early if T is close to zero as further samples won't affect the result much
						if (smokeTransmittance <= 0.01) {
							break;
						}
					}
			    }
				*/
			    
			    //float4 fire = tex2D(_FireGradient, float2(fireTransmittance,0)) * (1.0-fireTransmittance);
			    //float4 smoke = tex2D(_SmokeGradient, float2(smokeTransmittance,0)) * (1.0-smokeTransmittance);

				//float3 backgroundCol = 1;
				//float4 smokeCol = lightEnergy * _LightColor0; // * tex2D(_SmokeGradient, float2(smokeTransmittance,0))
				//float4 smokeCol = tex2D(_SmokeGradient, float2(smokeTransmittance,0));
				float4 smokeCol = float4(lightEnergy, 0.0, 0.0, 1.0);
                //smokeCol = backgroundCol * smokeTransmittance + smokeCol;

				//float4 smokeCol = tex2D(_SmokeGradient, float2(smokeTransmittance,0));
			    //float4 smoke = smokeCol * transmittance;

                return smokeCol;
			    
				//return fire + smoke;
				//return smoke;
			}
			
			ENDCG

    	}
	}
}





















