using UnityEngine;
using System.Collections;
using System.Collections.Generic;

namespace FluidSim3DProject
{
	public class Volumetric : MonoBehaviour 
	{
        public const string HEADER_DECORATION = " --- ";

        [Header (HEADER_DECORATION + "Core settings" + HEADER_DECORATION)]
        public FireFluidSim simulator;

        [Header (HEADER_DECORATION + "Marching settings" + HEADER_DECORATION)]
		public Texture2D blueNoise;
		public float rayOffsetStrength = 1.0f;


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

		public GameObject light;


        void Start() {
            simulator.Init(); //Initialize fire fluid
			this.SetParametersOnMaterial();

            Transform boundingBoxTransform = this.transform.parent;
			Debug.Log("_BoundingPosition: " + boundingBoxTransform.localPosition);
			Debug.Log("_BoundingScale: " + boundingBoxTransform.localScale);
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
        }

        void Update() {
            simulator.Simulate(); //Simulate fire fluid
			this.SetParametersOnMaterial();
        }

		void SetParametersOnMaterial() {
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
			material.SetBuffer("_Density", this.simulator.GetDensity());
			material.SetBuffer("_Reaction", this.simulator.GetReaction());
			material.SetVector("_Size", this.simulator.GetComputeSize());

		}

        void OnDestroy() {
            simulator.ReleaseAll();
        }

		void Lightmarch(Vector3 rayWorldPos, BoundingBox boundingBox) {
			Vector3 lightPos = light.transform.position;
			Ray rayTowardsLight = new Ray(); //Ray from cloud particle position to light position.
			rayTowardsLight.origin = rayWorldPos;
			rayTowardsLight.dir = Vector3.Normalize(lightPos - rayWorldPos);
			float dstInsideBox = rayBoundsDistance(rayTowardsLight, boundingBox).y; //Confirmed!!!
			//float dstToBox = rayBoundsDistance(rayTowardsLight, boundingBox).x; //Confirmed!!!
  
			float RAY_STEPS_TO_LIGHT = 8;
			float stepSize = dstInsideBox/RAY_STEPS_TO_LIGHT;
			//float totalDensity = 0;

			Vector3 lightRayPos = rayWorldPos;
			for (int step = 0; step < RAY_STEPS_TO_LIGHT; step ++) {
				lightRayPos += rayTowardsLight.dir * stepSize;
				Debug.Log("lightRayPos: " + lightRayPos);
				this.lightRayObjs[step].transform.position = lightRayPos;
			}
		}

		void Test() {
			Vector3 cameraPos = Camera.main.transform.position;

			Ray ray = new Ray();
			ray.origin = cameraPos;
			ray.dir = Vector3.Normalize(this.vertPos.transform.position - cameraPos);

			BoundingBox boundingBox = new BoundingBox();
			Transform boundingBoxTransform = this.transform.parent;
			Vector3 s = boundingBoxTransform.localScale;
			Vector3 p = boundingBoxTransform.localPosition;
			boundingBox.Min = new Vector3(-0.5f * s.x, -0.5f * s.y, -0.5f * s.z) + p;
			boundingBox.Max = new Vector3(0.5f * s.x, 0.5f * s.y, 0.5f * s.z) + p;

			this.Lightmarch(this.vertPos.transform.position, boundingBox);

			Vector2 rayToContainerInfo = rayBoundsDistance(ray, boundingBox);
			float dstToBox = rayToContainerInfo.x;
			float dstInsideBox = rayToContainerInfo.y;
			if (dstToBox < 0.0f) dstToBox = 0.0f;

			Vector3 entryPoint = ray.origin + ray.dir * dstToBox;
			Vector3 exitPoint = ray.origin + ray.dir * dstInsideBox;
 
			this.entryPointObj.transform.position = entryPoint;
			this.exitPointObj.transform.position = exitPoint;

			float RAY_STEPS_TO_FLUID = 64;
			float stepSize = Vector3.Distance(exitPoint, entryPoint)/RAY_STEPS_TO_FLUID;
			Vector3 ds = Vector3.Normalize(exitPoint-entryPoint) * stepSize;
			//Debug.Log("stepSize: " + stepSize);

			float dstTravelled = 0; //start is entryPoint
			float dstLimit = dstInsideBox - dstToBox; //end is exitPoint
			Vector3 rayPos = entryPoint;
			int cnt = 0;
			while (dstTravelled < dstLimit) {
				rayPos = entryPoint + ray.dir * dstTravelled; //
				//Vector3 tmp = (rayPos - p + 0.5f*s);
				//Vector3 rayPosOnUVW = new Vector3(tmp.x / s.x, tmp.y / s.y, tmp.z / s.z);
				/*
				Debug.Log("entryPoint: " + entryPoint);
				Debug.Log("ray.dir: " + ray.dir);
				Debug.Log("dstTravelled: " + dstTravelled);
				Debug.Log("=====================");
				*/

				this.rayObjs[cnt].transform.position = rayPos;
				dstTravelled += stepSize;
				cnt++;
				//rayPos += ds;
			}
			Debug.Log("while cnt: " + cnt);
		}

		public class Ray {
			public Vector3 origin;
			public Vector3 dir;
		}
		public class BoundingBox {
			public Vector3 Min;
			public Vector3 Max;
		}

		Vector2 rayBoundsDistance(Ray ray, BoundingBox boundingBox)
		{
			//Vector3 inverseRayDir = 1.0f / ray.dir;
			Vector3 inverseRayDir = new Vector3(1.0f / ray.dir.x, 1.0f / ray.dir.y, 1.0f / ray.dir.z);
			Vector3 v1 = (boundingBox.Min-ray.origin);
			Vector3 v2 = (boundingBox.Max-ray.origin);
			Vector3 tbot = new Vector3(inverseRayDir.x * v1.x, inverseRayDir.y * v1.y, inverseRayDir.z * v1.z);
			Vector3 ttop = new Vector3(inverseRayDir.x * v2.x, inverseRayDir.y * v2.y, inverseRayDir.z * v2.z);
			Vector3 tmin = Vector3.Min(ttop, tbot);
			Vector3 tmax = Vector3.Max(ttop, tbot);
			Vector2 t = Vector2.Max(new Vector2(tmin.x, tmin.x), new Vector2(tmin.y, tmin.z));
			float distanceIntersectedToNearBounds = Mathf.Max(t.x, t.y);
			t = Vector2.Min(new Vector2(tmax.x, tmax.x), new Vector2(tmax.y, tmax.z));
			float distanceIntersectedToFarBounds = Mathf.Min(t.x, t.y);

			return new Vector2(distanceIntersectedToNearBounds, distanceIntersectedToFarBounds);
		}

    }
}