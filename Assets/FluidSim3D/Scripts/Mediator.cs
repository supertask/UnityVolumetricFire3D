using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace FluidSim3DProject
{
    public class Mediator : MonoBehaviour
    {

        public FireFluidSim fluidSimulator3D;
        public GameObject spawnsObj;
        public Volumetric volumetric;

        [HideInInspector] public List<Spawn> spawns;
        [HideInInspector] public Bounds bounds;
        //private List<Velocity> spawnVelocities;


        void Start() {
            this.initColleagues();
            this.bounds = new Bounds(this.transform.position, this.transform.localScale);
            foreach(Spawn spawn in spawns) {
                spawn.InitSpawn(); //set voxels
            }
            this.fluidSimulator3D.Init(); //Initialize fire fluid
			this.volumetric.SetParametersOnMaterial();
        }

        void initColleagues() {
            if (spawnsObj == null) {
                Debug.LogError("Can't find spawns gameObject.");
                return;
            }
            if (fluidSimulator3D == null) {
                Debug.LogError("Can't find FluidSimulator3D.");
                return;
            }
            if (volumetric == null) {
                Debug.LogError("Can't find Volumetric.");
                return;
            }
            foreach(Transform spawnTransform in spawnsObj.transform) {
                if (spawnTransform.gameObject.GetComponent<Spawn>() != null) {
                    Spawn spawn = spawnTransform.gameObject.GetComponent<Spawn>();
                    spawn.SetMediator(this);
                    this.spawns.Add(spawn);
                }
            }
            this.fluidSimulator3D.SetMediator(this);
            this.volumetric.SetMediator(this);
        }

        void Update() {
            foreach(Spawn spawn in spawns) {
                spawn.UpdateSpawn();
            }
            this.fluidSimulator3D.Simulate(); //Simulate fire fluid
			this.volumetric.SetParametersOnMaterial();
        }


        void OnDestroy() {
            this.fluidSimulator3D.ReleaseAll();
        }

    }
}