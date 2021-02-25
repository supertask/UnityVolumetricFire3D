//#define UNIT_RP__URP
#define UNIT_RP__HDRP
#include "./FireRayMarchingCore.hlsl"

void FireRayMarching_float(
    float3 positionWS,
    float2 screenUV,
    float3 mainCameraPos,
    float3 mainLightPosition,
    float3 mainLightColor,
    out float3 color,
    out float alpha
) {
    float4 res = volumetricRayMarching(
        positionWS,
        screenUV,
        mainCameraPos,
        mainLightPosition,
        mainLightColor
    );
    color = res.rgb;
    alpha = res.a;
}
