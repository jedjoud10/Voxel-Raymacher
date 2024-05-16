﻿using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Voxel {
        public int texture;
        public static int size = 64;
        public static int levels = Math.Min(Int32.Log2(size), 7);
        Compute generation;
        Compute propagate;

        /* Memory Optimizations:
         * Sparse textures
         * Maybe lossless compression
         * Use bitwise stuff for acceleration levels
         * 
         * Speed optimizations:
         * Temporal depth reprojection from last frame (use it as "starting point" for iter)
         * AABB tree
         * Use bitwise stuff for acceleration levels
         * Keep history of local child indices of un-hit child to avoid retracing from the top
        */

        public Voxel() {
            /*
            int sparse = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, sparse);
            int a = 1;
            GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.TextureSparseArb, ref a);

            // TODO: This could be done once per internal format. For now, just do it every time.
            int bestIndex = -1,
                    bestXSize = 0,
                    bestYSize = 0,
                    bestZSize = 0;
            GL.GetInternalformat(ImageTarget.Texture3D, SizedInternalFormat.Rg32ui, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.NumVirtualPageSizesArb, 1, out int indexCount);

            if (indexCount == 0) {
                throw new Exception("NO PAGES!!!");
            }


            for (int i = 0; i < indexCount; ++i) {
                int copied = i;
                GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeIndexArb, ref copied);

                GL.GetInternalformat(ImageTarget.Texture3D, SizedInternalFormat.Rg32ui, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeXArb, 1, out int xSize);
                GL.GetInternalformat(ImageTarget.Texture3D, SizedInternalFormat.Rg32ui, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeXArb, 1, out int ySize);
                GL.GetInternalformat(ImageTarget.Texture3D, SizedInternalFormat.Rg32ui, (InternalFormatParameter)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeXArb, 1, out int zSize);

                Console.WriteLine($"X: {xSize}, Y: {ySize}, Z: {zSize}");

                if (xSize >= bestXSize && ySize >= bestYSize && zSize >= bestZSize) {
                    bestIndex = i;
                    bestXSize = xSize;
                    bestYSize = ySize;
                    bestZSize = zSize;
                }
            }

            GL.TexParameterI(TextureTarget.Texture3D, (TextureParameterName)OpenTK.Graphics.OpenGL4.ArbSparseTexture.VirtualPageSizeIndexArb, ref bestIndex);
            */
            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            GL.TextureStorage3D(texture, levels, SizedInternalFormat.Rg32ui, size, size, size);

            int testSize = size;
            for (int i = 0; i < levels; i++) {
                //GL.Ext.TexturePageCommitment(texture, i, 0, 0, 0, testSize, testSize, testSize, true);
                testSize /= 2;
                testSize = Math.Max(testSize, 1);
            }

            generation = new Compute("Voxel.glsl");
            propagate = new Compute("VoxelPropagate.glsl");
            
            GL.UseProgram(generation.program);
            GL.BindImageTexture(0, texture, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rg32ui);
            GL.DispatchCompute(size / 4, size / 4, size / 4);

            testSize = size;
            GL.UseProgram(propagate.program);
            for (int i = 0; i < levels-1; i++) {
                GL.BindImageTexture(0, texture, i, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.Rg32ui);
                GL.BindImageTexture(1, texture, i+1, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rg32ui);
                testSize /= 2;
                testSize = Math.Max(testSize, 1);

                int dispatches = (int)MathF.Ceiling((float)testSize / 4.0f);
                GL.DispatchCompute(dispatches, dispatches, dispatches);
                GL.MemoryBarrier(MemoryBarrierFlags.ShaderImageAccessBarrierBit);
            }
        }

        public void Bind(int startingUnit) {
            for (int i = 0; i < levels; i++) {
                GL.BindImageTexture(i + startingUnit, texture, i, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.Rg32ui);
            }
        }
    }
}
