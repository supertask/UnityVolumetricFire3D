Shader "VolumetricFire3D/URP/FireRayMarching"
{
    Properties
    { }

    SubShader
    {
        Tags {
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalRenderPipeline"
        }

        // No culling or depth
        Cull Off
        ZWrite Off
        ZTest Always

        //col.xyz * col.w + backCol.xyz * (1 - col.w)
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #define UNIT_RP__URP

            // The Core.hlsl file contains definitions of frequently used HLSL
            // macros and functions, and also contains #include references to other
            // HLSL files (for example, Common.hlsl, SpaceTransforms.hlsl, etc.).
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"            
            #include "./FireRayMarching.hlsl"

            ENDHLSL
        }
    }
}