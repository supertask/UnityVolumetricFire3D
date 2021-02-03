using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace FluidSim3DProject
{
    public class Mediator : MonoBehaviour
    {

        public FireFluidSim fluidSimulator3D;
        public GameObject spawnsObj;
        public GameObject obstaclesObj;
        public Volumetric volumetric;

        [HideInInspector] public List<Spawn> spawns;
        [HideInInspector] public List<Obstacle> obstacles;
        [HideInInspector] public Bounds bounds;
        //private List<Velocity> spawnVelocities;


        void Start() {
            this.initColleagues();
            this.bounds = new Bounds(this.transform.position, this.transform.localScale);
            foreach(Spawn spawn in spawns) {
                spawn.InitSpawn(); //set voxels
            }
            foreach(Obstacle obstacle in obstacles) {
                obstacle.InitObstacle(); //set voxels
            }
            this.fluidSimulator3D.Init(); //Initialize fire fluid
			this.volumetric.SetParametersOnMaterial();
        }

        void initColleagues() {
            if (spawnsObj == null) {
                Debug.LogError("Can't find spawns gameObject.");
                return;
            }
            if (obstaclesObj == null) {
                Debug.LogError("Can't find obstacles gameObject.");
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
                Spawn spawn = spawnTransform.gameObject.GetComponent<Spawn>();
                if (spawn != null) {
                    spawn.SetMediator(this);
                    this.spawns.Add(spawn);
                }
            }
            foreach(Transform obstacleTransform in obstaclesObj.transform) {
                Obstacle obstacle = obstacleTransform.gameObject.GetComponent<Obstacle>();
                if (obstacle != null) {
                    obstacle.SetMediator(this);
                    this.obstacles.Add(obstacle);
                }
            }
            this.fluidSimulator3D.SetMediator(this);
            this.volumetric.SetMediator(this);
        }

        void Update() {
            foreach(Spawn spawn in spawns) {
                spawn.UpdateSpawn();
            }
            foreach(Obstacle obstacle in obstacles) {
                obstacle.UpdateObstacle();
            }
            this.fluidSimulator3D.Simulate(); //Simulate fire fluid
			this.volumetric.SetParametersOnMaterial();
        }


        void OnDestroy() {
            this.fluidSimulator3D.ReleaseAll();
        }

    }
}