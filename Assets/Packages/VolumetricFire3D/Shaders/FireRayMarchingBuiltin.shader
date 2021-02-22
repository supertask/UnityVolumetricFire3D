// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'


Shader "VolumetricFire3D/Builtin/FireRayMarching" 
{
	Properties
	{
		//_FireGradient("FireGradient", 2D) = "red" {}
		//_SmokeGradient("SmokeGradient", 2D) = "white" {}

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

			#define UNIT_RP__BUILT_IN_RP
			#include "UnityCG.cginc"
			#include "./FireRayMarchingCore.hlsl"

			#pragma target 5.0
			#pragma vertex vert
			#pragma fragment frag
			
			ENDCG

    	}
	}
}





















