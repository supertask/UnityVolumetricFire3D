Shader "VolumetricFire3D/HDRP/FireRayMarching"
{
    Properties
    { }

    SubShader
    {
        Tags {
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
            "RenderPipeline" = "HDRenderPipeline"
        }

        Pass
        {
            // No culling or depth
            Cull Off
            ZWrite Off
            ZTest Always 

            //col.xyz * col.w + backCol.xyz * (1 - col.w)
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #define UNIT_RP__HDRP

            // The Core.hlsl file contains definitions of frequently used HLSL
            // macros and functions, and also contains #include references to other
            // HLSL files (for example, Common.hlsl, SpaceTransforms.hlsl, etc.).
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
            #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/Lighting.hlsl"
            //#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Sky/SkyUtils.hlsl"

            #include "./FireRayMarchingCore.hlsl"

            ENDHLSL
        }
    }
}