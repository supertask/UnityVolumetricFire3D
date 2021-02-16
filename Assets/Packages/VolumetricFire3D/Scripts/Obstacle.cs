using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

using UnityEngine;
using UnityEngine.Rendering;

using VoxelSystem;


namespace FluidSim3DProject
{

    public class Obstacle : MeshVoxelizer {
        public void InitObstacle () {
            base.InitMeshVoxelizer();
        }

        public void UpdateObstacle () {
            base.UpdateMeshVoxelizer();
        }

    }

}

