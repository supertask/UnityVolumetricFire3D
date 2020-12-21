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


        [SerializeField] protected ComputeShader voxelizer;
        public int numOfVoxels = 128;

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

        protected GPUVoxelData gpuVoxelData;

        void InitSpawn () {
            var mesh = SampleMesh();
            if (mesh == null) return;
            gpuVoxelData = GPUVoxelizer.Voxelize(voxelizer, mesh, numOfVoxels, true);
        }
        
        void UpdateSpawn () {
            if (gpuVoxelData == null) return;

            gpuVoxelData.Dispose();

            var mesh = SampleMesh();
            if (mesh == null) return;
            gpuVoxelData = GPUVoxelizer.Voxelize(voxelizer, mesh, numOfVoxels, true);
        }

        public GPUVoxelData GetGPUVoxelData() {
            return this.gpuVoxelData;
        }

        Mesh SampleMesh()
        {
            if (this.GetComponent<MeshRenderer>() != null) {
                return this.GetComponent<MeshFilter>().mesh;
            }
            else if (this.GetComponent<SkinnedMeshRenderer>() != null) {
                var mesh = new Mesh();
                this.GetComponent<SkinnedMeshRenderer>().BakeMesh(mesh);
                return mesh;
            } else {
                Debug.LogError("Attach MeshRenderer or SkinnedMeshRenderer on a Spawn Object");
                return null;
            }
        }

        void OnDestroy ()
        {
            if(gpuVoxelData != null)
            {
                gpuVoxelData.Dispose();
                gpuVoxelData = null;
            }
        }

    }

}

