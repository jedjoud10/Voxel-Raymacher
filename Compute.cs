using OpenTK.Graphics.OpenGL4;
using OpenTK.Mathematics;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Compute {
        public int program;
        public Compute(string path) {
            string execPath = System.Reflection.Assembly.GetEntryAssembly().Location;
            execPath = Path.GetDirectoryName(execPath);
            
            string global = Path.Combine(execPath, "Resources", path);
            string source = File.ReadAllText(global);

            int temp = GL.CreateShader(ShaderType.ComputeShader);
            GL.ShaderSource(temp, source);
            GL.CompileShader(temp);
            program = GL.CreateProgram();
            GL.AttachShader(program, temp);
            GL.LinkProgram(program);

            Console.WriteLine(GL.GetShaderInfoLog(temp));
            Console.WriteLine(GL.GetProgramInfoLog(program));
            GL.ValidateProgram(program);
        }  
    }
}
