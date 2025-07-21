# 🌀 Ellis Wormhole Shader (GLSL / ShaderToy)

A physically accurate rendering of an Ellis wormhole based on real geometry no shortcuts or raymarching cheats
This shader simulates geodesic motion through a wormhole using actual differential geometry dynamically warping light paths and offering a realistic visual transition between two seperate areas

Based on another shader i saw on shadertoy
some logic was kept but most rewritten 

<table>
  <tr>
    <td><img src="Screenshot 2025-07-22 004021.png" width="400"/></td>
    <td><img src="Screenshot 2025-07-22 004028.png" width="400"/></td>
  </tr>
</table>

- Move through the wormhole: automatic camera motion (`sin(iTime)`)
- Look around: click + drag mouse

To test the shader live, paste the code into [ShaderToy](https://www.shadertoy.com/new) and assign:
- `iChannel0` → front cubemap
- `iChannel1` → back cubemap

## ⚖️ License

MIT — feel free to modify, credit appr
