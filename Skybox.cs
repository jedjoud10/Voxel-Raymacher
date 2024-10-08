﻿using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Skybox {
        public int texture;
        public static int size = 64;
        Compute generation;
        Compute test;

        Matrix4[] matrices = new Matrix4[6] {
                Matrix4.LookAt(Vector3.Zero, -Vector3.UnitX, -Vector3.UnitY),
                Matrix4.LookAt(Vector3.Zero, Vector3.UnitX, -Vector3.UnitY),
                Matrix4.LookAt(Vector3.Zero, Vector3.UnitY, Vector3.UnitZ),
                Matrix4.LookAt(Vector3.Zero, -Vector3.UnitY, -Vector3.UnitZ),
                Matrix4.LookAt(Vector3.Zero, Vector3.UnitZ, -Vector3.UnitY),
                Matrix4.LookAt(Vector3.Zero, -Vector3.UnitZ, -Vector3.UnitY),
        };

        public Skybox(Vector3 sun) {
            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.TextureCubeMap, texture);
            GL.TextureStorage2D(texture, 1, SizedInternalFormat.Rgba8, size, size);
            GL.TextureParameter(texture, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Nearest);
            GL.TextureParameter(texture, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Nearest);

            generation = new Compute("Skybox.glsl");
        }

        public void Update(float time, Vector3 sun) {
            for (int i = 0; i < 6; i++) {
                GL.UseProgram(generation.program);
                GL.BindImageTexture(0, texture, 0, false, i, TextureAccess.WriteOnly, SizedInternalFormat.Rgba8);
                GL.ProgramUniformMatrix4(generation.program, 1, false, ref matrices[i]);
                GL.ProgramUniform1(generation.program, 2, size);
                //GL.ProgramUniform1(generation.program, 4, time);
                GL.ProgramUniform3(generation.program, 5, sun);
                GL.DispatchCompute(size / 4, size / 4, 1);
            }
            
        }
    }
}
