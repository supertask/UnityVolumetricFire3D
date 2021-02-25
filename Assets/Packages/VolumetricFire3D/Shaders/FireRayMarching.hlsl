#include "./FireRayMarchingCore.hlsl"


v2f vert(VertexInput v)
{
    v2f OUT;

    #if defined(UNIT_RP__BUILT_IN_RP)
        OUT.positionWS = mul(unity_ObjectToWorld, v.positionOS).xyz; //world space position
        OUT.positionCS = UnityObjectToClipPos(v.positionOS); //clip space position
    #elif defined(UNIT_RP__HDRP) || defined(UNIT_RP__URP)
        OUT.positionWS = TransformObjectToWorld(v.positionOS); //world space position
        OUT.positionCS = TransformWorldToHClip(OUT.positionWS); //clip space position
    #endif

    // Screen position
    //https://gamedev.stackexchange.com/questions/129139/how-do-i-calculate-uv-space-from-world-space-in-the-fragment-shader
    OUT.screenPos = OUT.positionCS.xyw;
    // Correct flip when rendering with a flipped projection matrix.
    // (I've observed this differing between the Unity scene & game views)
    OUT.screenPos.y *= _ProjectionParams.x; //For multi-platform like VR

    /*
    //
    // Get view vector
    //
    // Ref. Clouds
    // Camera space matches OpenGL convention where cam forward is -z. In unity forward is positive z.
    // (https://docs.unity3d.com/ScriptReference/Camera-cameraToWorldMatrix.html)
    float2 screenUV = (OUT.screenPos.xy / OUT.screenPos.z) * 0.5f + 0.5f;

    #if defined(UNIT_RP__BUILT_IN_RP) || defined(UNIT_RP__URP)
        float3 viewVector = mul(unity_CameraInvProjection, float4(screenUV * 2 - 1, 0, -1));
        OUT.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));
    #elif defined(UNIT_RP__HDRP)
    #endif
    */

    return OUT;
}


float4 frag(v2f IN) : COLOR
{
    float2 screenUV = (IN.screenPos.xy / IN.screenPos.z) * 0.5f + 0.5f;

    //float viewLength = length(IN.viewVector);

    #if defined(UNIT_RP__BUILT_IN_RP)
        float3 mainLightPosition = _WorldSpaceLightPos0;
        float3 mainLightColor = _LightColor0;
        float3 mainCameraPos = _WorldSpaceCameraPos; 
    #elif defined(UNIT_RP__HDRP)
        DirectionalLightData light = _DirectionalLightDatas[0];
        float3 mainLightPosition = -light.forward.xyz;
        float3 mainLightColor = light.color;
        float3 mainCameraPos = _WorldSpaceCameraPos; 
    #elif defined(UNIT_RP__URP)
        float3 mainLightPosition = _MainLightPosition;
        float3 mainLightColor = _MainLightColor;
        float3 mainCameraPos = _WorldSpaceCameraPos; 
    #endif

    return volumetricRayMarching(
        IN.positionWS,
        screenUV,
        mainCameraPos,
        mainLightPosition,
        mainLightColor
    );
}
