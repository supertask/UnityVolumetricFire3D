using UnityEngine;
using System.Collections;

namespace FluidSim3DProject
{
	public class Volumetric : MonoBehaviour 
	{
        public FireFluidSim simulator;

        void Start() {
            simulator.Init(); //Initialize fire fluid
        }

        void Update() {
            simulator.Simulate(); //Simulate fire fluid

            Transform parent = this.transform.parent;

			//rotation of box not support because ray cast in shader uses a AABB intersection
			parent.rotation = Quaternion.identity;
			
			GetComponent<Renderer>().material.SetVector("_Translate", parent.localPosition);
			GetComponent<Renderer>().material.SetVector("_Scale", parent.localScale);
			GetComponent<Renderer>().material.SetBuffer("_Density", this.simulator.GetDensity());
			GetComponent<Renderer>().material.SetBuffer("_Reaction", this.simulator.GetReaction());
			GetComponent<Renderer>().material.SetVector("_Size", this.simulator.GetComputeSize());
        }

        void OnDestroy() {
            simulator.ReleaseAll();
        }
    }
}