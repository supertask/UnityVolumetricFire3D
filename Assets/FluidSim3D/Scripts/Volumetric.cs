using UnityEngine;
using System.Collections;
using System.Collections.Generic;


namespace FluidSim3DProject
{
	public class Volumetric : MonoBehaviour 
	{
        public const string HEADER_DECORATION = " --- ";

        //[Header (HEADER_DECORATION + "Core settings" + HEADER_DECORATION)]
        //public FireFluidSim simulator;

        [Header (HEADER_DECORATION + "Marching settings" + HEADER_DECORATION)]
		public Texture2D blueNoise;
		public float rayOffsetStrength = 1.0f;

		[Header (HEADER_DECORATION + "Base Shape" + HEADER_DECORATION)]
		public Texture3D baseShapeNoise;
		public Vector4 shapeNoiseWeights = new Vector4(1, 0.48f, 0.15f, 0);
		public float densityOffset = -4.27f;
		public float cloudScale = 0.6f;
		//public float densityMultiplier = 1.0f;

		[Header (HEADER_DECORATION + "Fire fluid settings" + HEADER_DECORATION)]

		public Color skyColor;
		public float fireAbsorption = 40.0f;
		public float smokeAbsorption = 60.0f;

		[Header (HEADER_DECORATION + "Lighting" + HEADER_DECORATION)]
		public float lightAbsorptionTowardSun = 1.21f;
		public float lightAbsorptionThroughCloud = 0.75f;
		[Range(0, 10)] public float darknessThreshold = 0.15f;

		[Range (0, 1)] public float forwardScattering = 0.811f;
		[Range (0, 1)] public float backScattering = 0.33f;
		[Range (0, 10)] public float baseBrightness = 1.0f; //should be 1, maybe
		[Range (0, 1)] public float phaseFactor = 0.488f;

		[Header (HEADER_DECORATION + "Debug" + HEADER_DECORATION)]
		public GameObject vertPos;
		public GameObject entryPointObj;
		public GameObject exitPointObj;
		public List<GameObject> rayObjs;
		public List<GameObject> lightRayObjs;

		private Mediator mediator; //Knows everything


        //void Start() {

			/*
            Transform boundingBoxTransform = this.transform.parent;
			//Debug.Log("_BoundingPosition: " + boundingBoxTransform.localPosition);
			//Debug.Log("_BoundingScale: " + boundingBoxTransform.localScale);
			this.rayObjs = new List<GameObject>();
			for(int i=0; i < 64 + 5; i++) {
				GameObject obj = Object.Instantiate(vertPos) as GameObject;
				obj.name = "ray" + i;
				obj.transform.position = Vector3.zero;
				this.rayObjs.Add(obj);
			}
			for(int i=0; i < 8; i++) {
				GameObject obj = Object.Instantiate(vertPos) as GameObject;
				obj.name = "lightRay" + i;
				obj.transform.position = Vector3.zero;
				this.lightRayObjs.Add(obj);
			}
			Test();
			*/
        //}

		public void SetMediator(Mediator mediator) {
			this.mediator = mediator;
		}

		public void SetParametersOnMaterial() {
            Transform boundingBoxTransform = this.transform.parent.parent;
            Material material = this.GetComponent<Renderer>().material;

			material.SetTexture ("NoiseTex", baseShapeNoise);
			material.SetVector ("_ShapeNoiseWeights", shapeNoiseWeights);
			material.SetFloat ("_DensityOffset", densityOffset);
			material.SetFloat ("_CloudScale", cloudScale);
			//material.SetFloat ("_DensityMultiplier", densityMultiplier);
			//Debug.Log("noise: " + noiseGen.shapeTexture);
            
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
			//Debug.Log("_LightAbsorptionThroughCloud: " + lightAbsorptionThroughCloud);
			material.SetColor("_SkyColor", skyColor);

            //
            // Fire fluid values
            //
			//rotation of box not support because ray cast in shader uses a AABB intersection
			boundingBoxTransform.rotation = Quaternion.identity;
			
			//Debug.Log("_BoundingPosition: " + boundingBoxTransform.localPosition);
			//Debug.Log("_BoundingScale: " + boundingBoxTransform.localScale);
			material.SetVector("_BoundingPosition", boundingBoxTransform.localPosition);
			material.SetVector("_BoundingScale", boundingBoxTransform.localScale);
			material.SetBuffer("_Density", this.mediator.fluidSimulator3D.GetDensity());
			material.SetBuffer("_Reaction", this.mediator.fluidSimulator3D.GetReaction());
			material.SetBuffer("_Temperature", this.mediator.fluidSimulator3D.GetTemperature());
			material.SetVector("_Size", this.mediator.fluidSimulator3D.GetComputeSize());

		}



    }
}