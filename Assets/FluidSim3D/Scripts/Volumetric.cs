using UnityEngine;
using System.Collections;

namespace FluidSim3DProject
{

    //[ExecuteInEditMode, ImageEffectAllowedInSceneView]
	//Volumetric ray marching shader
	public class Volumetric : MonoBehaviour 
	{
		public const string HEADER_DECORATION = " --- ";

		[Header (HEADER_DECORATION + "Core" + HEADER_DECORATION)]

		public FireFluidSim simulator;
		//public Shader shader;
		public Material material;
		
		[Header (HEADER_DECORATION + "Marching settings" + HEADER_DECORATION)]
		public Texture2D blueNoise;
		public float rayOffsetStrength = 10.0f;


		[Header (HEADER_DECORATION + "Fire fluid settings" + HEADER_DECORATION)]
		public float fireAbsorption = 60.0f;
		public float smokeAbsorption = 40.0f;

		[Header (HEADER_DECORATION + "Lighting" + HEADER_DECORATION)]
		[Range(0, 2)] public float lightAbsorptionTowardSun = 1.21f;
		[Range(0, 2)] public float lightAbsorptionThroughCloud = 0.75f;
		[Range(0, 1)] public float darknessThreshold = 0.15f;

		[Range (0, 1)] public float forwardScattering = 0.811f;
		[Range (0, 1)] public float backScattering = 0.33f;
		[Range (0, 1)] public float baseBrightness = 1.0f;
		[Range (0, 1)] public float phaseFactor = 0.488f;


		public void SetParameters() {
			//Debug.Log("SetParameters on Volumetric.cs");
			Transform boundsTransform = this.transform.parent;
			this.material.SetVector ("boundsMin", boundsTransform.position - boundsTransform.localScale / 2);
			this.material.SetVector ("boundsMax", boundsTransform.position + boundsTransform.localScale / 2);

			this.material.SetTexture ("BlueNoise", blueNoise);
			this.material.SetVector ("_PhaseParams", new Vector4 (forwardScattering, backScattering, baseBrightness, phaseFactor));
			this.material.SetFloat ("_RayOffsetStrength", rayOffsetStrength);

			this.material.SetFloat("_FireAbsorption", fireAbsorption);
			this.material.SetFloat("_SmokeAbsorption", smokeAbsorption);
			this.material.SetFloat("_LightAbsorptionTowardSun", lightAbsorptionTowardSun);
			this.material.SetFloat("_LightAbsorptionThroughCloud", lightAbsorptionThroughCloud);
			this.material.SetFloat("_DarknessThreshold", darknessThreshold);


			this.material.SetVector("_Translate", boundsTransform.localPosition);
			this.material.SetVector("_BoundsScale", boundsTransform.localScale);

		}

/*
		[ImageEffectOpaque]
        private void OnRenderImage (RenderTexture src, RenderTexture dest) {
			// Validate inputs
			//if (material == null) { return; }
			if (material == null || material.shader != shader) {
				material = new Material (shader);
			}

            this.SetParameters();
            Graphics.Blit (src, dest, this.material);
        }
		*/

			/*
		void Update() {
			if (simulator == null) {
				Debug.Log("Input simulator.");
				return;
			}
			if (material == null) {
				Debug.Log("Input material.");
				return;
			}
			this.material.SetBuffer("_Density", simulator.GetDensity());
			this.material.SetBuffer("_Reaction", simulator.GetReaction());
			this.material.SetVector("_VoxelSize", simulator.GetComputeSize());
		}*/
	}

}