using System.Collections;
using System.Collections.Generic;
using UnityEngine;


namespace FluidSim3DProject
{

    [ExecuteInEditMode, ImageEffectAllowedInSceneView]
    public class RayMarching : MonoBehaviour
    {
        public Volumetric volumetric; //TODO(Tasuku): required

        [ImageEffectOpaque]
        private void OnRenderImage (RenderTexture src, RenderTexture dest) {
            volumetric.SetParameters();
            Graphics.Blit (src, dest, volumetric.material);
        }
    }
}