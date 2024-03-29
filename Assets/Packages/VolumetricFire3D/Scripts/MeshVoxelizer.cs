﻿using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

using UnityEngine;
using UnityEngine.Rendering;

using VoxelSystem;


namespace FluidSim3DProject
{

    public class MeshVoxelizer : MonoBehaviour {


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

        private GPUVoxelizer gpuVoxelizer;

        private Mesh defaultMesh; //mesh before replacing to voxel meshes
        private Material defaultMaterial; //material before replacing to voxel meshes

        private float normalizedObjectRadius;
        private Vector3 normalizedObjectPosition;

        public void InitMeshVoxelizer () {
            var mesh = SampleMesh();
            if (mesh == null) return;
            //defaultMesh = mesh;
            //defaultMaterial =this.spawnObj.GetComponent<MeshRenderer>().sharedMaterial;

            Bounds fireBounds = this.mediator.bounds;
            Bounds spawnBounds = this.spawnObj.GetComponent<Renderer>().bounds;
            //Debug.Log("box min: " + this.mediator.bounds.min);
            //Debug.Log("box center: " + this.mediator.bounds.center);
            //Debug.Log("box size: " + this.mediator.bounds.size);
            //Debug.Log("spawn box center: " + spawnBounds.center);
            //Debug.Log("spawn box min: " + spawnBounds.min);
            //Debug.Log("spawn box max: " + spawnBounds.max);
            //Debug.Log("spawn box extends: " + spawnBounds.extents);
            //Debug.Log("spawn box size: " + spawnBounds.size);
            //Debug.Log("spawn mesh box center: " + mesh.bounds.center);
            //Debug.Log("spawn mesh box size: " + mesh.bounds.size);

            this.SetObjectCenter();
            this.SetObjectRadius();

            numOfVoxels = Mathf.ClosestPowerOfTwo(this.mediator.fluidSimulator3D.m_width);

            this.gpuVoxelizer = new GPUVoxelizer();
            this.gpuVoxelizer.InitVoxelization(mesh, this.mediator.bounds, numOfVoxels);
            this.voxelsInBounds = gpuVoxelizer.Voxelize(voxelizer, mesh, this.spawnObj.transform, true);

            this.GetComponent<MeshFilter>().sharedMesh = VoxelMesh.Build(this.voxelsInBounds.GetData(), this.voxelsInBounds.UnitLength, true);

            //Debug.LogFormat("!!!!!!!!!!!!!!!!!!!!! Num of triangles: {0}", mesh.triangles.Length);
        }

        
        public void UpdateMeshVoxelizer () {
            if (this.voxelsInBounds == null) return;

            /*if (type == MeshVisualType.Mesh) {
                //this.spawnObj.GetComponent<MeshFilter>().sharedMesh = defaultMesh;
            } else if (type == MeshVisualType.Voxel) {
                //this.spawnObj.GetComponent<MeshFilter>().sharedMesh = null;
            } else if (type == MeshVisualType.None) {
                //this.spawnObj.GetComponent<MeshFilter>().sharedMesh = null;
            }*/

            this.SetObjectCenter();
            this.SetObjectRadius();

            var mesh = SampleMesh();
            if (mesh == null) return;
            this.voxelsInBounds = gpuVoxelizer.Voxelize(voxelizer, mesh, this.spawnObj.transform, true);

            //Debug.LogFormat("Num of triangles: {0}", mesh.triangles.Length);

        }

        public void SetMediator(Mediator mediator) {
			this.mediator = mediator;
		}

        public GPUVoxelData GetGPUVoxelData() {
            return this.voxelsInBounds;
        }


        public void SetObjectCenter() {
            Bounds fireBounds = this.mediator.bounds;
            //Normalized spawn object position in bounds
            Vector3 localSpawnCenter = this.spawnObj.transform.position - fireBounds.min;
            this.normalizedObjectPosition = new Vector3(
                localSpawnCenter.x / fireBounds.size.x,
                localSpawnCenter.y / fireBounds.size.y,
                localSpawnCenter.z / fireBounds.size.z);
            //Debug.LogFormat("Spawn Object position: {0}", this.normalizedObjectPosition);
        }
        public void SetObjectRadius() {
            Bounds fireBounds = this.mediator.bounds;
            Bounds spawnBounds = this.spawnObj.GetComponent<Renderer>().bounds;

            //Normalized spawn object radius in bounds
            //Vector3 localSpawnCenter = this.spawnObj.transform.position - fireBounds.min;
            Vector3 localSpawnExtends = spawnBounds.max - fireBounds.min;
            //Debug.LogFormat("localSpawnExtends: {0}", localSpawnExtends);
            Vector3 normalizedObjectExtendsPosition = new Vector3(
                localSpawnExtends.x / fireBounds.size.x,
                localSpawnExtends.y / fireBounds.size.y,
                localSpawnExtends.z / fireBounds.size.z);
            //Debug.LogFormat("normalizedObjectExtendsPosition: {0}", normalizedObjectExtendsPosition);

            Vector3 normalizedObjectExtends = normalizedObjectExtendsPosition - this.normalizedObjectPosition;
            //Debug.LogFormat("normalizedObjectExtends: {0}", normalizedObjectExtends);

            //this.normalizedObjectRadius = Mathf.Sqrt(distX * distX + distY * distY + distZ * distZ);
            this.normalizedObjectRadius = Mathf.Max(Mathf.Max(normalizedObjectExtends.x, normalizedObjectExtends.y), normalizedObjectExtends.z);
            //Debug.LogFormat("Spawn Object Radius: {0}", this.normalizedObjectRadius);
        }

        public Vector3 GetObjectCenter() {
            return this.normalizedObjectPosition;
        }

        public float GetObjectRadius() {
            return this.normalizedObjectRadius;
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

            this.gpuVoxelizer.ReleaseAll();
        }

    }

}

