using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

using UnityEngine;
using UnityEngine.Rendering;

using VoxelSystem;


namespace FluidSim3DProject
{

    public class Spawn : MonoBehaviour {


        [SerializeField] protected GameObject spawnObj;
        // [SerializeField] protected Material voxelMaterial;
        [SerializeField] protected ComputeShader voxelizer;

        private int numOfVoxels;

        protected Kernel setupKernel, updateKernel;
        protected ComputeBuffer particleBuffer;

        protected Renderer _renderer;
        protected MaterialPropertyBlock block;

        #region Shader property keys

        protected const string kSetupKernelKey = "Setup", kUpdateKernelKey = "Update";

        protected const string kVoxelBufferKey = "_VoxelBuffer", kVoxelCountKey = "_VoxelCount";
        protected const string kParticleBufferKey = "_ParticleBuffer", kParticleCountKey = "_ParticleCount";
        protected const string kUnitLengthKey = "_UnitLength";

        #endregion

        protected GPUVoxelData voxelsInBounds;

        private Mediator mediator; //Knows everything

        enum MeshVisualType {
            Mesh, Voxel, None
        };

        [SerializeField] MeshVisualType type = MeshVisualType.Voxel;

        private Mesh defaultMesh; //mesh before replacing to voxel meshes
        private Material defaultMaterial; //material before replacing to voxel meshes

        private float spawnObjRadius;

        public void InitSpawn () {
            var mesh = SampleMesh();
            if (mesh == null) return;
            //defaultMesh = mesh;
            //defaultMaterial =this.spawnObj.GetComponent<MeshRenderer>().sharedMaterial;


            Debug.Log("box center: " + this.mediator.bounds.center);
            Debug.Log("box size: " + this.mediator.bounds.size);
            Debug.Log("mesh box center: " + mesh.bounds.center);
            Debug.Log("mesh box size: " + mesh.bounds.size);

            
            float distX = mesh.bounds.extents.x - mesh.bounds.center.x;
            float distY = mesh.bounds.extents.y - mesh.bounds.center.y;
            float distZ = mesh.bounds.extents.z - mesh.bounds.center.z;
            this.spawnObjRadius = Mathf.Sqrt(distX * distX + distY * distY + distZ * distZ);
            Debug.LogFormat("Spawn Object Radius: {0}", this.spawnObjRadius);

            numOfVoxels = Mathf.ClosestPowerOfTwo(this.mediator.fluidSimulator3D.m_width);
            voxelsInBounds = GPUVoxelizer.Voxelize(voxelizer, mesh, this.spawnObj.transform, this.mediator.bounds, numOfVoxels, true);

            this.GetComponent<MeshFilter>().sharedMesh = VoxelMesh.Build(voxelsInBounds.GetData(), voxelsInBounds.UnitLength, true);

        }

        
        public void UpdateSpawn () {
            if (voxelsInBounds == null) return;

            if (type == MeshVisualType.Mesh) {
                //this.spawnObj.GetComponent<MeshFilter>().sharedMesh = defaultMesh;
            } else if (type == MeshVisualType.Voxel) {
                //this.spawnObj.GetComponent<MeshFilter>().sharedMesh = null;
            } else if (type == MeshVisualType.None) {
                //this.spawnObj.GetComponent<MeshFilter>().sharedMesh = null;
            }

/*
            voxelsInBounds.Dispose();

            var mesh = SampleMesh();
            if (mesh == null) return;
            Debug.LogFormat("mesh.triangles: {0}", mesh.triangles);
            voxelsInBounds = GPUVoxelizer.Voxelize(voxelizer, mesh, this.spawnObj.transform, this.mediator.bounds, numOfVoxels, true);
            */

        }

        public void SetMediator(Mediator mediator) {
			this.mediator = mediator;
		}

        public GPUVoxelData GetGPUVoxelData() {
            return this.voxelsInBounds;
        }

        public Vector3 GetSpawnCenter() {
            return this.spawnObj.transform.position;
        }

        public float GetSpawnRadius() {
            return this.spawnObjRadius;
        }


        // Get mesh from a set object
        Mesh SampleMesh()
        {
            //if (defaultMesh != null) { return defaultMesh; }
            if (this.spawnObj.GetComponent<MeshRenderer>() != null) {
                return this.spawnObj.GetComponent<MeshFilter>().mesh;
            }
            else if (this.spawnObj.GetComponent<SkinnedMeshRenderer>() != null) {
                var mesh = new Mesh();
                this.spawnObj.GetComponent<SkinnedMeshRenderer>().BakeMesh(mesh);
                return mesh;
            } else {
                Debug.LogError("Attach MeshRenderer or SkinnedMeshRenderer on a Spawn Object");
                return null;
            }
        }

        void OnDestroy ()
        {
            if(particleBuffer != null)
            {
                particleBuffer.Release();
                particleBuffer = null;
            }

            if(voxelsInBounds != null)
            {
                voxelsInBounds.Dispose();
                voxelsInBounds = null;
            }
        }

    }

}

