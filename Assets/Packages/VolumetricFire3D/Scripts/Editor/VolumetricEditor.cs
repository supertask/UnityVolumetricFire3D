using UnityEngine;

#if UNITY_EDITOR
using UnityEditor;
#endif

using System.IO;
using System.Collections;

namespace FluidSim3DProject
{
    #if UNITY_EDITOR
    [CustomEditor(typeof(Volumetric))]
    public class VolumetricEditor : Editor {

        public override void OnInspectorGUI() 
        {
            EditorGUI.BeginChangeCheck();
            base.OnInspectorGUI();

            Volumetric volumetric = target as Volumetric;

            if (EditorGUI.EndChangeCheck())
            {
                //Debug.Log("end change ");
                this.serializedObject.ApplyModifiedProperties();
                volumetric.RenderTexutures();
            }
        }

    }
    #endif
}