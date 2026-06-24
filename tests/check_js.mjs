// Синтаксическая проверка LuCI-вьюх (deno).
// LuCI исполняет файл как тело функции (верхнеуровневый return, 'require'-строки),
// поэтому new Function(src) компилирует его без выполнения и ловит syntax errors.
let bad = 0;
for (const path of Deno.args) {
	let src;
	try { src = await Deno.readTextFile(path); }
	catch (e) { console.error('READERR', path, e.message); bad++; continue; }
	try { new Function(src); console.log('  ok   ' + path); }
	catch (e) { console.error('  FAIL ' + path + ' :: ' + e.message); bad++; }
}
if (bad) { console.error('\nsyntax errors: ' + bad); Deno.exit(1); }
console.log('\nJS syntax OK');
