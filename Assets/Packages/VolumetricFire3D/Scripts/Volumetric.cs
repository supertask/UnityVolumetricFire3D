using UnityEngine;
using System.Collections;
using System.Collections.Generic;

using mattatz.Utils;

namespace FluidSim3DProject
{
	public class Volumetric : MonoBehaviour 
	{
        public const string HEADER_DECORATION = " --- ";

        //[Header (HEADER_DECORATION + "Core settings" + HEADER_DECORATION)]
        //public FireFluidSim simulator;

		[Header (HEADER_DECORATION + "Base Shape" + HEADER_DECORATION)]
		public float densityOffset = 150;
		public float reactionOffset = 100;

		[Header (HEADER_DECORATION + "Fire fluid settings" + HEADER_DECORATION)]

		public List<Gradient> gradients = new List<Gradient>();
		public List<RenderTexture> renderTextures = new List<RenderTexture>();

		/*
		public Gradient fireGradient;
		public Gradient smokeGradient;

		public RenderTexture fireRenderTexture;
		public RenderTexture smokeRenderTexture;
		*/

		public float fireAbsorption = 40.0f;
		public float smokeAbsorption = 60.0f;

		[Header (HEADER_DECORATION + "Lighting" + HEADER_DECORATION)]
		public float lightAbsorptionTowardSun = 1.21f;
		public float lightAbsorptionThroughCloud = 0.75f;
		[Range(0, 1)] public float darknessThreshold = 0.15f;

		[Range (0, 1)] public float forwardScattering = 0.811f;
		[Range (0, 1)] public float backScattering = 0.33f;
		[Range (0, 10)] public float baseBrightness = 1.0f; //should be 1, maybe
		[Range (0, 1)] public float phaseFactor = 0.488f;

		public float fireIntensity = 1.0f;


		private Mediator mediator; //Knows everything


        void Start() {
			this.RenderTexutures();
        }

		public void SetMediator(Mediator mediator) {
			this.mediator = mediator;
		}

		public void SetParametersOnMaterial() {
            Transform boundingBoxTransform = this.transform.parent.parent;
            Material material = this.GetComponent<Renderer>().material;

			material.SetTexture ("FireGradient", renderTextures[0]);
			material.SetTexture ("SmokeGradient", renderTextures[1]);

			material.SetFloat ("_FireIntensity", fireIntensity);
			material.SetFloat ("_DensityOffset", densityOffset);
			material.SetFloat ("_ReactionOffset", reactionOffset);
            
            material.SetVector ("boundsMin", boundingBoxTransform.position - boundingBoxTransform.localScale / 2);
			material.SetVector ("boundsMax", boundingBoxTransform.position + boundingBoxTransform.localScale / 2);

			material.SetVector ("_PhaseParams", new Vector4 (forwardScattering, backScattering, baseBrightness, phaseFactor));

			material.SetFloat("_FireAbsorption", fireAbsorption);
			material.SetFloat("_SmokeAbsorption", smokeAbsorption);
			material.SetFloat("_LightAbsorptionTowardSun", lightAbsorptionTowardSun);
			material.SetFloat("_LightAbsorptionThroughCloud", lightAbsorptionThroughCloud);
			material.SetFloat("_DarknessThreshold", darknessThreshold);
			//Debug.Log("_LightAbsorptionThroughCloud: " + lightAbsorptionThroughCloud);

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

		public void RenderTexutures() {
			Texture2D fireTexture = GradientTexGen.Create(this.gradients[0], 512);
			Graphics.Blit(fireTexture, this.renderTextures[0]);
			Texture2D smokeTexture = GradientTexGen.Create(this.gradients[1], 512);
			Graphics.Blit(smokeTexture, this.renderTextures[1]);
		}

    }
}