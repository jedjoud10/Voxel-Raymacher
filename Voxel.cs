using OpenTK.Graphics.OpenGL4;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Voxel {
        int texture;
        Compute generation;

        public Voxel() {
            int size = 64;
            texture = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture3D, texture);
            GL.TextureStorage3D(texture, 4, SizedInternalFormat.R8ui, size, size, size);

            generation = new Compute("Voxel.glsl");

            GL.UseProgram(generation.program);
            GL.ActiveTexture(TextureUnit.Texture0);
            GL.BindImageTexture(0, texture, 0, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.R8ui);
            GL.BindImageTexture(1, texture, 1, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.R8ui);
            GL.BindImageTexture(2, texture, 2, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.R8ui);
            GL.BindImageTexture(3, texture, 3, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.R8ui);
            GL.DispatchCompute(size / 4, size / 4, size / 4);
        }

        public void Bind(int program) {
            GL.ActiveTexture(TextureUnit.Texture1);
            GL.BindImageTexture(1, texture, 0, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.R8ui);
            GL.BindImageTexture(2, texture, 1, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.R8ui);
            GL.BindImageTexture(3, texture, 2, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.R8ui);
            GL.BindImageTexture(4, texture, 3, false, 0, TextureAccess.ReadOnly, SizedInternalFormat.R8ui);
        }
    }
}
