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
        int texture;
        int levels;
        Compute generation;

        public Voxel() {
            int size = 512;
            levels = Int32.Log2(size) - 2;
            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            GL.TextureStorage3D(texture, levels, SizedInternalFormat.R32ui, size, size, size);

            generation = new Compute("Voxel.glsl");

            GL.UseProgram(generation.program);
            GL.ActiveTexture(TextureUnit.Texture0);

            for (int i = 0; i < levels; i++) {
                GL.BindImageTexture(i, texture, i, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.R32ui);
            }
            
            GL.DispatchCompute(size / 4, size / 4, size / 4);
        }

        public void Bind(int program) {
            GL.ActiveTexture(TextureUnit.Texture1);

            for (int i = 0; i < levels; i++) {
                GL.BindImageTexture(i+1, texture, i, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.R32ui);
            }
        }
    }
}
