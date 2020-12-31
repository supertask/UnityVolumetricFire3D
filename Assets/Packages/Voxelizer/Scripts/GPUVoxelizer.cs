using System;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

using UnityEngine;
using UnityEngine.Rendering;

namespace VoxelSystem {

	public class GPUVoxelizer {

		protected const string kVolumeKernelKey = "Volume", kSurfaceFrontKernelKey = "SurfaceFront", kSurfaceBackKernelKey = "SurfaceBack", kTextureKernelKey = "BuildTexture3D";
		protected const string kStartKey = "_Start", kEndKey = "_End", kSizeKey = "_Size";
		protected const string kMeshPositionKey = "_MeshPosition", kMeshRotationKey = "_MeshRotation", kMeshScaleKey = "_MeshScale";
		protected const string kUnitKey = "_Unit", kInvUnitKey = "_InvUnit", kHalfUnitKey = "_HalfUnit";
		protected const string kWidthKey = "_Width", kHeightKey = "_Height", kDepthKey = "_Depth";
		protected const string kTriCountKey = "_TrianglesCount", kTriIndexesKey = "_TriangleIndexes";
		protected const string kVertBufferKey = "_VertBuffer", kUVBufferKey = "_UVBuffer", kTriBufferKey = "_TriBuffer";
		protected const string kVoxelBufferKey = "_VoxelBuffer", kVoxelTextureKey = "_VoxelTexture";
        protected const string kColorTextureKey = "_ColorTexture";

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

		public static GPUVoxelData Voxelize(ComputeShader voxelizer, Mesh mesh, int resolution = 32, bool volume = true, bool pow2 = true) {
			mesh.RecalculateBounds();
            return Voxelize(voxelizer, mesh, mesh.bounds, resolution, volume, pow2);
		}

        public static GPUVoxelData Voxelize(ComputeShader voxelizer, Mesh mesh, Bounds bounds, int resolution = 32, bool volume = true, bool pow2 = true) {
			mesh.RecalculateBounds();
            return Voxelize(voxelizer, mesh,Vector3.zero, Quaternion.Euler(0, 0, 0), Vector3.one, 
                bounds, resolution, volume, pow2);
		}
        public static GPUVoxelData Voxelize(ComputeShader voxelizer, Mesh mesh, Transform meshTransform, Bounds bounds, int resolution = 32, bool volume = true, bool pow2 = true) {
			mesh.RecalculateBounds();
            return Voxelize(voxelizer, mesh, meshTransform.position, meshTransform.rotation, meshTransform.localScale,
                bounds, resolution, volume, pow2);
		}

        public static GPUVoxelData Voxelize(
            ComputeShader voxelizer,
            Mesh mesh,
            Vector3 meshPosition,
            Quaternion meshRotation,
            Vector3 meshScale, //global scale
            Bounds bounds,
            int resolution = 32,
            bool volume = true,
            bool pow2 = false
        ) {
			var vertices = mesh.vertices;
			var vertBuffer = new ComputeBuffer(vertices.Length, Marshal.SizeOf(typeof(Vector3)));
			vertBuffer.SetData(vertices);

			var uvBuffer = new ComputeBuffer(vertBuffer.count, Marshal.SizeOf(typeof(Vector2)));
            if(mesh.uv.Length > 0)
            {
                var uv = mesh.uv;
                uvBuffer.SetData(uv);
            }

			var triangles = mesh.triangles; //TODO(Tasuku): bug
			var triBuffer = new ComputeBuffer(triangles.Length, Marshal.SizeOf(typeof(int))); //TODO(Tasuku): bug
			triBuffer.SetData(triangles);

			var maxLength = Mathf.Max(bounds.size.x, Mathf.Max(bounds.size.y, bounds.size.z));
			var unit = maxLength / resolution;
            var hunit = unit * 0.5f;

            // Extend (min & max) to voxelize boundary surface correctly.
            var start = bounds.min - new Vector3(hunit, hunit, hunit);
            var end = bounds.max + new Vector3(hunit, hunit, hunit);
            var size = end - start;

            int w, h, d;
            if(!pow2) {
                w = Mathf.CeilToInt(size.x / unit);
                h = Mathf.CeilToInt(size.y / unit);
                d = Mathf.CeilToInt(size.z / unit);
                Debug.Log("!pow2");
            } else  {
                w = GetNearPow2(size.x / unit);
                h = GetNearPow2(size.y / unit);
                d = GetNearPow2(size.z / unit);
                Debug.Log("pow2");
            }
            Debug.LogFormat("position:{0}", meshPosition);
            Debug.LogFormat("rotation:{0}", meshRotation);
            Debug.LogFormat("scale:{0}", meshScale);
            Debug.LogFormat("w: {0}, h: {1}, d: {2}", w, h, d);
            Debug.LogFormat("resolution: {0}, unit: {1}", resolution, unit);

			var voxelBuffer = new ComputeBuffer(w * h * d, Marshal.SizeOf(typeof(Voxel_t)));
            var voxels = new Voxel_t[voxelBuffer.count];
            Debug.LogFormat("voxels count: {0}", voxelBuffer.count);
            voxelBuffer.SetData(voxels); // initialize voxels explicitly

			// send bounds
			voxelizer.SetVector(kStartKey, start);
			voxelizer.SetVector(kEndKey, end);
			voxelizer.SetVector(kSizeKey, size);

            // send position, rotation, and scale
			voxelizer.SetVector(kMeshPositionKey, meshPosition);
			voxelizer.SetVector(kMeshRotationKey, new Vector4(meshRotation.x, meshRotation.y, meshRotation.z, meshRotation.w) );
			voxelizer.SetVector(kMeshScaleKey, meshScale);

			voxelizer.SetFloat(kUnitKey, unit);
			voxelizer.SetFloat(kInvUnitKey, 1f / unit);
			voxelizer.SetFloat(kHalfUnitKey, hunit);
			voxelizer.SetInt(kWidthKey, w);
			voxelizer.SetInt(kHeightKey, h);
			voxelizer.SetInt(kDepthKey, d);

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
                voxelizer.Dispatch(volumeKer.Index, w / (int)volumeKer.ThreadX + 1, h / (int)volumeKer.ThreadY + 1, (int)surfaceFrontKer.ThreadZ);
            }

			// dispose
			vertBuffer.Release();
			uvBuffer.Release();
			triBuffer.Release();

			return new GPUVoxelData(voxelBuffer, w, h, d, unit);
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

