using UnityEngine;
using System.Collections;

namespace FluidSim3DProject
{
	public class Volumetric : MonoBehaviour 
	{
        public const string HEADER_DECORATION = " --- ";

        [Header (HEADER_DECORATION + "Core settings" + HEADER_DECORATION)]
        public FireFluidSim simulator;

        [Header (HEADER_DECORATION + "Marching settings" + HEADER_DECORATION)]
		public Texture2D blueNoise;
		public float rayOffsetStrength = 10.0f;


		[Header (HEADER_DECORATION + "Fire fluid settings" + HEADER_DECORATION)]
		public float fireAbsorption = 40.0f;
		public float smokeAbsorption = 60.0f;

		[Header (HEADER_DECORATION + "Lighting" + HEADER_DECORATION)]
		[Range(0, 2)] public float lightAbsorptionTowardSun = 1.21f;
		[Range(0, 2)] public float lightAbsorptionThroughCloud = 0.75f;
		[Range(0, 1)] public float darknessThreshold = 0.15f;

		[Range (0, 1)] public float forwardScattering = 0.811f;
		[Range (0, 1)] public float backScattering = 0.33f;
		[Range (0, 1)] public float baseBrightness = 1.0f;
		[Range (0, 1)] public float phaseFactor = 0.488f;

        void Start() {
            simulator.Init(); //Initialize fire fluid
        }

        void Update() {
            simulator.Simulate(); //Simulate fire fluid

            Transform boundingBoxTransform = this.transform.parent;
            Material material = this.GetComponent<Renderer>().material;
            
            material.SetVector ("boundsMin", boundingBoxTransform.position - boundingBoxTransform.localScale / 2);
			material.SetVector ("boundsMax", boundingBoxTransform.position + boundingBoxTransform.localScale / 2);

			material.SetTexture ("BlueNoise", blueNoise);
			material.SetVector ("_PhaseParams", new Vector4 (forwardScattering, backScattering, baseBrightness, phaseFactor));
			material.SetFloat ("_RayOffsetStrength", rayOffsetStrength);

			material.SetFloat("_FireAbsorption", fireAbsorption);
			material.SetFloat("_SmokeAbsorption", smokeAbsorption);
			material.SetFloat("_LightAbsorptionTowardSun", lightAbsorptionTowardSun);
			material.SetFloat("_LightAbsorptionThroughCloud", lightAbsorptionThroughCloud);
			material.SetFloat("_DarknessThreshold", darknessThreshold);


            //
            // Fire fluid values
            //
			//rotation of box not support because ray cast in shader uses a AABB intersection
			boundingBoxTransform.rotation = Quaternion.identity;
			
			material.SetVector("_Translate", boundingBoxTransform.localPosition);
			material.SetVector("_Scale", boundingBoxTransform.localScale);
			material.SetBuffer("_Density", this.simulator.GetDensity());
			material.SetBuffer("_Reaction", this.simulator.GetReaction());
			material.SetVector("_Size", this.simulator.GetComputeSize());
        }

        void OnDestroy() {
            simulator.ReleaseAll();
        }
    }
}