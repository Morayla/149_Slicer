import {build} from 'esbuild';import fs from 'node:fs';import {Script} from 'node:vm';
await build({entryPoints:['src/app.js'],bundle:true,format:'iife',target:['safari16','chrome110'],outfile:'dist/app.js',minify:true});
const js=fs.readFileSync('dist/app.js','utf8').replaceAll('</script','<\\/script');new Script(js);
const html=fs.readFileSync('src/index.html','utf8').replace('<!--STYLE-->',()=>`<style>${fs.readFileSync('src/style.css','utf8')}</style>`).replace('<!--APPEARANCE-->',()=>`<script>${fs.readFileSync('src/appearance.js','utf8')}</script>`).replace('<!--SCRIPT-->',()=>`<script>${js}</script>`);
fs.mkdirSync('dist',{recursive:true});fs.writeFileSync('dist/calibration.html',html);console.log('149 calibration workspace built:',Math.round(html.length/1024),'KB');
