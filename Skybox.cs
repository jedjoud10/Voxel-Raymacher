using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Skybox {
        public int texture;
        public static int size = 64;
        Compute generation;

        public Skybox() {
            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.TextureCubeMap, texture);
            GL.TextureStorage2D(texture, 1, SizedInternalFormat.Rgba8, size, size);

            generation = new Compute("Skybox.glsl");
            GL.UseProgram(generation.program);

            Matrix4[] matrices = new Matrix4[6] {
                Matrix4.LookAt(Vector3.Zero, -Vector3.UnitX, -Vector3.UnitY),
                Matrix4.LookAt(Vector3.Zero, Vector3.UnitX, -Vector3.UnitY),
                Matrix4.LookAt(Vector3.Zero, Vector3.UnitY, Vector3.UnitZ),
                Matrix4.LookAt(Vector3.Zero, -Vector3.UnitY, -Vector3.UnitZ),
                Matrix4.LookAt(Vector3.Zero, Vector3.UnitZ, -Vector3.UnitY),
                Matrix4.LookAt(Vector3.Zero, -Vector3.UnitZ, -Vector3.UnitY),
            };

            for (int i = 0; i < 6; i++) {
                GL.BindImageTexture(0, texture, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rgba8);
                GL.ProgramUniformMatrix4(generation.program, 1, false, ref matrices[i]);
                GL.ProgramUniform1(generation.program, 2, size);
                GL.ProgramUniform1(generation.program, 3, i);
                GL.DispatchCompute(size / 4, size / 4, 1);
            }
        }
    }
}
