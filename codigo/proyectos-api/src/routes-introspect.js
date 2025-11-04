export function routesIntrospect(app) {
  const out = [];
  function walk(stack, prefix="") {
    for (const layer of stack) {
      if (layer.route && layer.route.path) {
        const methods = Object.keys(layer.route.methods).filter(m => layer.route.methods[m]);
        out.push({ path: prefix + layer.route.path, methods });
      } else if (layer.name === "router" && layer.handle?.stack) {
        let p = layer.regexp?.source || "";
        p = p.replace("^\\","/").replace("\\/?(?=\\/|$)","/").replaceAll("\\","").replaceAll("^","").replaceAll("$","");
        walk(layer.handle.stack, p || prefix);
      }
    }
  }
  walk(app._router.stack);
  return out;
}
