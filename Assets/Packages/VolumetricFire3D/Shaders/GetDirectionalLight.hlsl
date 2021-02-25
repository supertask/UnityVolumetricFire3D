//#if defined(GETLIGHT_INCLUDED)
//#define GETLIGHT_INCLUDED


//#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
//#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" 

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightDefinition.cs.hlsl"


void GetDirectionalLight_float(out float3 Direction, out float3 Color)
{
    Direction = half3(0, 0, 0);
    Color = 0;

#if SHADERGRAPH_PREVIEW
    Direction = half3(0.5, 0.5, 0);
    Color = 1;
#else
    #if defined(UNIT_RP__HDRP)
        if (_DirectionalLightCount > 0) {
            DirectionalLightData light = _DirectionalLightDatas[0];
            Direction = -light.forward.xyz;
            Color = light.color;
        } else {
            Direction = float3(1, 0, 0);
            Color = 0;
        }
    #elif defined(UNIT_RP__URP)
        Light light = GetMainLight();
        Direction = light.direction;
        Color = light.color;
    #endif
#endif

    /*
    #if defined(UNIT_RP__HDRP)
    if (_DirectionalLightCount > 0)
    {
        DirectionalLightData light = _DirectionalLightDatas[0];
        lightDir = -light.forward.xyz;
        color = light.color;
    }
    #elif defined(UNIT_RP__URP)
        //lightDir = _WorldSpaceLightPos0;
        //color = _LightColor0;
    #endif
    */
//#endif

}

