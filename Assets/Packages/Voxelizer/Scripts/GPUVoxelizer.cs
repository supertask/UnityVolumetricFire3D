using System;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

using UnityEngine;
using UnityEngine.Rendering;

namespace VoxelSystem {

	public class GPUVoxelizer {

		protected const string kVolumeKernelKey = "Volume", kSurfaceFrontKernelKey = "SurfaceFront", kSurfaceBackKernelKey = "SurfaceBack";
        protected const string kTextureKernelKey = "BuildTexture3D", kResetVoxelsKernelKey = "ResetVoxels";

		protected const string kStartKey = "_Start", kEndKey = "_End", kSizeKey = "_Size";
		protected const string kMeshPositionKey = "_MeshPosition", kMeshRotationKey = "_MeshRotation", kMeshScaleKey = "_MeshScale";
		protected const string kUnitKey = "_Unit", kInvUnitKey = "_InvUnit", kHalfUnitKey = "_HalfUnit";
		protected const string kWidthKey = "_Width", kHeightKey = "_Height", kDepthKey = "_Depth";
		protected const string kTriCountKey = "_TrianglesCount", kTriIndexesKey = "_TriangleIndexes";
		protected const string kVertBufferKey = "_VertBuffer", kUVBufferKey = "_UVBuffer", kTriBufferKey = "_TriBuffer";
		protected const string kVoxelBufferKey = "_VoxelBuffer", kVoxelTextureKey = "_VoxelTexture";
        protected const string kColorTextureKey = "_ColorTexture";

        private ComputeBuffer vertBuffer, triBuffer, uvBuffer, voxelBuffer;
        private Vector3 voxelBoundsStart, voxelBoundsEnd, voxelBoundsSize;
        private int resolutionWidth, resolutionHeight, resolutionDepth;
        private float unit, halfUnit;

/*
        public static int GetNearPow2(float n)
        {
            if(n <= 0) {
                return 0;
            }
            Debug.LogFormat("GetNearPow2 n:{0}", n);
            var k = Mathf.CeilToInt(Mathf.Log(n, 2));
            Debug.LogFormat("GetNearPow2 2^k:{0}", k);
            return (int)Mathf.Pow(2, k);
        }
        */


        public void InitVoxelization(
            Mesh mesh,
            Bounds bounds,
            int resolution = 32,
            bool pow2 = true
        ) {

            //
            // Bounding & resolusion settings 
            //
			var maxLength = Mathf.Max(bounds.size.x, Mathf.Max(bounds.size.y, bounds.size.z));
			this.unit = maxLength / resolution;
            this.halfUnit = this.unit * 0.5f;

            // Extend (min & max) to voxelize boundary surface correctly.
            this.voxelBoundsStart = bounds.min - new Vector3(this.halfUnit, this.halfUnit, this.halfUnit);
            this.voxelBoundsEnd = bounds.max + new Vector3(this.halfUnit, this.halfUnit, this.halfUnit);
            this.voxelBoundsSize = voxelBoundsEnd - voxelBoundsStart;

            if(!pow2) {
                this.resolutionWidth = Mathf.CeilToInt(this.voxelBoundsSize .x / this.unit);
                this.resolutionHeight = Mathf.CeilToInt(this.voxelBoundsSize .y / this.unit);
                this.resolutionDepth = Mathf.CeilToInt(this.voxelBoundsSize .z / this.unit);
                Debug.Log("!pow2");
            } else  {
                this.resolutionWidth = Mathf.ClosestPowerOfTwo((int)(this.voxelBoundsSize .x / this.unit));
                this.resolutionHeight = Mathf.ClosestPowerOfTwo((int)(this.voxelBoundsSize .y / this.unit));
                this.resolutionDepth = Mathf.ClosestPowerOfTwo((int)(this.voxelBoundsSize .z / this.unit));
                Debug.Log("pow2");
            }
            Debug.LogFormat("w: {0}, h: {1}, d: {2}", this.resolutionWidth, this.resolutionHeight, this.resolutionDepth);
            Debug.LogFormat("resolution: {0}, this.unit: {1}", resolution, this.unit);

			this.voxelBuffer = new ComputeBuffer(this.resolutionWidth * this.resolutionHeight * this.resolutionDepth,
                    Marshal.SizeOf(typeof(Voxel_t)));
            var voxels = new Voxel_t[this.voxelBuffer.count];
            Debug.LogFormat("voxels count: {0}", this.voxelBuffer.count);
            this.voxelBuffer.SetData(voxels); // initialize voxels explicitly. Takes a lot of times

            //
            // Compute buffers for a mesh
            //
			this.vertBuffer = new ComputeBuffer(mesh.vertices.Length, Marshal.SizeOf(typeof(Vector3)));
			this.vertBuffer.SetData(mesh.vertices);

			this.uvBuffer = new ComputeBuffer(vertBuffer.count, Marshal.SizeOf(typeof(Vector2)));
            if(mesh.uv.Length > 0) {
                uvBuffer.SetData(mesh.uv);
            }
			this.triBuffer = new ComputeBuffer(mesh.triangles.Length, Marshal.SizeOf(typeof(int)));
			this.triBuffer.SetData(mesh.triangles);

        }

        /*
        //
        //old version
        //
		public static GPUVoxelData Voxelize(ComputeShader voxelizer, Mesh mesh, int resolution = 32, bool volume = true, bool pow2 = true) {
			mesh.RecalculateBounds();
            return Voxelize(voxelizer, mesh, mesh.bounds, resolution, volume, pow2);
		}
        public static GPUVoxelData Voxelize(ComputeShader voxelizer, Mesh mesh, Bounds bounds, int resolution = 32, bool volume = true, bool pow2 = true) {
			mesh.RecalculateBounds();
            return Voxelize(voxelizer, mesh,Vector3.zero, Quaternion.Euler(0, 0, 0), Vector3.one, 
                bounds, resolution, volume, pow2);
		}
        */

        
        public GPUVoxelData Voxelize(
            ComputeShader voxelizer,
            Mesh mesh,
            Transform meshTransform,
            bool volume = true
        ) {
            return this.Voxelize(voxelizer, mesh, meshTransform.position, meshTransform.rotation,
                meshTransform.localScale, volume);
        }

        public GPUVoxelData Voxelize(
            ComputeShader voxelizer,
            Mesh mesh,
            Vector3 meshPosition,
            Quaternion meshRotation,
            Vector3 meshScale, //global scale
            bool volume = true
        ) {
            this.ResetVoxels(voxelizer);

            Debug.LogFormat("position:{0}", meshPosition);
            Debug.LogFormat("rotation:{0}", meshRotation);
            Debug.LogFormat("scale:{0}", meshScale);

            this.vertBuffer.SetData(mesh.vertices);
            if(mesh.uv.Length > 0) {
                this.uvBuffer.SetData(mesh.uv);
            }
			this.triBuffer.SetData(mesh.triangles);

			// send bounds
			voxelizer.SetVector(kStartKey, this.voxelBoundsStart);
			voxelizer.SetVector(kEndKey, this.voxelBoundsEnd);
			voxelizer.SetVector(kSizeKey, this.voxelBoundsSize);

            // send position, rotation, and scale
			voxelizer.SetVector(kMeshPositionKey, meshPosition);
			voxelizer.SetVector(kMeshRotationKey, new Vector4(meshRotation.x, meshRotation.y, meshRotation.z, meshRotation.w) );
			voxelizer.SetVector(kMeshScaleKey, meshScale);

			voxelizer.SetFloat(kUnitKey, this.unit);
			voxelizer.SetFloat(kInvUnitKey, 1f / this.unit);
			voxelizer.SetFloat(kHalfUnitKey, this.halfUnit);
			voxelizer.SetInt(kWidthKey, this.resolutionWidth);
			voxelizer.SetInt(kHeightKey, this.resolutionHeight);
			voxelizer.SetInt(kDepthKey, this.resolutionDepth);

			// send mesh data
			voxelizer.SetInt(kTriCountKey, triBuffer.count);
            var indexes = triBuffer.count / 3;
			voxelizer.SetInt(kTriIndexesKey, indexes);

            // surface front
			var surfaceFrontKer = new Kernel(voxelizer, kSurfaceFrontKernelKey);
			voxelizer.SetBuffer(surfaceFrontKer.Index, kVertBufferKey, vertBuffer);
			voxelizer.SetBuffer(surfaceFrontKer.Index, kUVBufferKey, uvBuffer);
			voxelizer.SetBuffer(surfaceFrontKer.Index, kTriBufferKey, triBuffer);
			voxelizer.SetBuffer(surfaceFrontKer.Index, kVoxelBufferKey, voxelBuffer);
			voxelizer.Dispatch(surfaceFrontKer.Index, indexes / (int)surfaceFrontKer.ThreadX + 1, (int)surfaceFrontKer.ThreadY, (int)surfaceFrontKer.ThreadZ);

            // surface back
			var surfaceBackKer = new Kernel(voxelizer, kSurfaceBackKernelKey);
			voxelizer.SetBuffer(surfaceBackKer.Index, kVertBufferKey, vertBuffer);
			voxelizer.SetBuffer(surfaceBackKer.Index, kUVBufferKey, uvBuffer);
			voxelizer.SetBuffer(surfaceBackKer.Index, kTriBufferKey, triBuffer);
			voxelizer.SetBuffer(surfaceBackKer.Index, kVoxelBufferKey, voxelBuffer);
			voxelizer.Dispatch(surfaceBackKer.Index, indexes / (int)surfaceBackKer.ThreadX + 1, (int)surfaceBackKer.ThreadY, (int)surfaceBackKer.ThreadZ);

            if(volume)
            {
			    var volumeKer = new Kernel(voxelizer, kVolumeKernelKey);
                voxelizer.SetBuffer(volumeKer.Index, kVoxelBufferKey, voxelBuffer);
                voxelizer.Dispatch(volumeKer.Index,
                    this.resolutionWidth / (int)volumeKer.ThreadX + 1,
                    this.resolutionHeight / (int)volumeKer.ThreadY + 1,
                    (int)surfaceFrontKer.ThreadZ);
            }

			return new GPUVoxelData(voxelBuffer, this.resolutionWidth, this.resolutionHeight, this.resolutionDepth, this.unit);
        }

        public void ResetVoxels(ComputeShader voxelizer) {
            var kernel = new Kernel(voxelizer, kResetVoxelsKernelKey);
			voxelizer.SetInt(kWidthKey, this.resolutionWidth);
			voxelizer.SetInt(kHeightKey, this.resolutionHeight);
			voxelizer.SetInt(kDepthKey, this.resolutionDepth);
			voxelizer.SetBuffer(kernel.Index, kVoxelBufferKey, this.voxelBuffer);
			voxelizer.Dispatch(kernel.Index,
                this.resolutionWidth / (int)kernel.ThreadX + 1,
                this.resolutionHeight / (int)kernel.ThreadY + 1,
                this.resolutionDepth / (int)kernel.ThreadZ + 1);
        }


        public void ReleaseAll() {
			// dispose
            if (this.vertBuffer != null) {
                this.vertBuffer.Release();
            }
            if (this.uvBuffer != null) {
                this.uvBuffer.Release();
            }
            if (this.triBuffer != null) {
                this.triBuffer.Release();
            }
            if (this.voxelBuffer != null) {
                this.voxelBuffer.Release();
            }
        }

        public static RenderTexture BuildTexture3D(ComputeShader voxelizer, GPUVoxelData data, RenderTextureFormat format, FilterMode filterMode)
        {
            return BuildTexture3D(voxelizer, data, Texture2D.whiteTexture, format, filterMode);
        }

        public static RenderTexture BuildTexture3D(ComputeShader voxelizer, GPUVoxelData data, Texture2D texture, RenderTextureFormat format, FilterMode filterMode)
        {
            var volume = CreateTexture3D(data, format, filterMode);

            var kernel = new Kernel(voxelizer, kTextureKernelKey);
			voxelizer.SetBuffer(kernel.Index, kVoxelBufferKey, data.Buffer);
			voxelizer.SetTexture(kernel.Index, kVoxelTextureKey, volume);
			voxelizer.SetTexture(kernel.Index, kColorTextureKey, texture);
			voxelizer.Dispatch(kernel.Index, data.Width / (int)kernel.ThreadX + 1, data.Height / (int)kernel.ThreadY + 1, data.Depth / (int)kernel.ThreadZ + 1);

            return volume;
        }

        static RenderTexture CreateTexture3D(GPUVoxelData data, RenderTextureFormat format, FilterMode filterMode)
        {
            var texture = new RenderTexture(data.Width, data.Height, 0, format, RenderTextureReadWrite.Default);
            texture.dimension = TextureDimension.Tex3D;
            texture.volumeDepth = data.Depth;
            texture.enableRandomWrite = true;
            texture.filterMode = filterMode;
            texture.wrapMode = TextureWrapMode.Clamp;
            texture.Create();

            return texture;
        }

	}

}

