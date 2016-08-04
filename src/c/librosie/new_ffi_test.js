//  -*- Mode: Javascript; -*-                                      
// 
//  new_ffi_test.js
// 
//  © Copyright IBM Corporation 2016.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings

//
// npm install ffi
//

var debug = require("debug");

var ffi = require("ffi");
var ref = require('ref');
var Struct = require('ref-struct');
var ArrayType = require('ref-array')

var DynamicLibrary = require('./node_modules/ffi/lib/dynamic_library')
  , ForeignFunction = require('./node_modules/ffi/lib/foreign_function')


var MyCString = Struct({
    'len': 'uint32',
    'ptr': ref.refType('CString')
});

var MyCStringArray = Struct({
    'n': 'uint32',
    'ptr': ref.refType(ref.refType(MyCString))
});

var MyCStringPtr = ref.refType(MyCString)

var RTLD_NOW = ffi.DynamicLibrary.FLAGS.RTLD_NOW;
var RTLD_GLOBAL = ffi.DynamicLibrary.FLAGS.RTLD_GLOBAL;
var mode = RTLD_NOW | RTLD_GLOBAL;

var RosieLib = new DynamicLibrary('librosie.so' || null, mode);

var funcs = {'initialize': [ 'int', ['string']],
	     'new_engine': [ MyCStringArray, [MyCStringPtr] ],
	     'rosie_api': [ MyCStringArray, ['string', MyCStringPtr, MyCStringPtr] ],
	     'free_stringArray': [ 'void', [MyCStringArray] ]
	    }

var Rosie = new ffi.Library;
Object.keys(funcs || {}).forEach(function (func) {
    debug('defining function', func)

    var fptr = RosieLib.get(func)
      , info = funcs[func]

    if (fptr.isNull()) {
      throw new Error('Library: "' + Libfile
        + '" returned NULL function pointer for "' + func + '"')
    }

    var resultType = info[0]
      , paramTypes = info[1]
      , fopts = info[2]
      , abi = fopts && fopts.abi
      , async = fopts && fopts.async
      , varargs = fopts && fopts.varargs

    if (varargs) {
      Rosie[func] = VariadicForeignFunction(fptr, resultType, paramTypes, abi)
    } else {
      var ff = ForeignFunction(fptr, resultType, paramTypes, abi)
      Rosie[func] = async ? ff.async : ff
    }
  })


var buf = ref.allocCString('hello world');
buf[3] = 0
console.log(buf.length, buf.toString());

var str = new MyCString
str.ptr = ref.allocCString("Hi!").ref()
str.len = str.ptr.deref().length
console.log("str.len =", str.len, " and str.ptr.length =", str.ptr.length)
console.log("str len=", str.len, " and ptr=", str.ptr.deref().toString("utf8",0,str.len))

console.log(buf.length, buf.toString());
var xx = buf.ref()
var x = xx.deref().reinterpret(Buffer.byteLength(buf.toString()))
x = x.ref()
console.log(buf.length, x.deref().toString().length, Buffer.byteLength(buf.toString()))
console.log("x is:", x, " x.length=", x.length, " and ptr=", x.deref().toString("utf8", 0, buf.length))
console.log("x.deref() is:", x.deref())
x.deref()[1]=0
console.log("x is:", x, " x.length=", x.length, " and ptr=", x.deref().toString("utf8", 0, buf.length))
console.log("x.deref() is:", x.deref())

function new_CString(str) {
    var cstr = new MyCString
    cstr.ptr = ref.allocCString(str)
    cstr.len = str.length
    return cstr
}

function extract_string_from_CString_ptr(cstr_ptr) {
    var cstr = ref.alloc(MyCString)
    cstr = cstr_ptr.deref()
    var buf = cstr.ptr.reinterpret(cstr.len)
    return buf.toString()
}    

function extract_string_from_array(stringarray, index) {
    var n = stringarray.n
    var p = stringarray.ptr
    if (index < n) {
	var cstr_ptr = ref.get(p, (index*ref.sizeof.pointer), MyCStringPtr)
	var str = extract_string_from_CString_ptr(cstr_ptr)
	return str
    }
    else return null
}

function print_array(retval) {
    var n = retval.n
    for (var i=0; i<n; i++) {
	var str = extract_string_from_array(retval, i)
	console.log("print_array: [", i, "] length =", str.length, " and value =", str)
    }
}

console.log("About to initialize Rosie")
var i = Rosie.initialize("/Users/jjennings/Work/Dev/rosie-pattern-language")
console.log("Return value from initialize: ", i)

var config = new MyCString
var tbl = {'name': 'JS test engine', 'expression':'[:digit:]+', 'encode':false}
var tmp = JSON.stringify(tbl)
config.ptr = ref.allocCString(tmp)
config.len = Buffer.byteLength(tmp)
var buf = config.ptr.reinterpret(config.len)
console.log(config.ptr.length, config.len, buf.toString("utf8", 0, config.len))

var i = ref.alloc(MyCStringArray)
i = Rosie.new_engine(config.ref())
console.log("Return value from new_engine is: ")
var code = extract_string_from_array(i, 0)
var eid = extract_string_from_array(i, 1)
print_array(i)
console.log("Engine id is: ", eid)

var ignored = new_CString("ignored")
var eid_CString = new_CString(eid)
console.log("Engine id as CString is: len =", eid_CString.len, "and ptr =", eid_CString.ptr.toString())

i = Rosie.rosie_api("inspect_engine", eid_CString.ref(), ignored.ref())
console.log("Return value from inspect_engine is: ")
print_array(i)

// Loop prep

var manifest = new_CString("$sys/MANIFEST")
console.log("manifest: len =", manifest.len, "value =", manifest.ptr.toString())

var retval = Rosie.rosie_api("load_manifest", eid_CString.ref(), manifest.ref())
print_array(retval)
Rosie.free_stringArray(retval)

var config = new_CString("{\"expression\" : \"[:digit:]+\", \"encode\" : \"json\"}")

retval = Rosie.rosie_api("configure_engine", eid_CString.ref(), config.ref())
print_array(retval)
Rosie.free_stringArray(retval)

var foo = new_CString("1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999")
var retval = Rosie.rosie_api("match", eid_CString.ref(), foo.ref())
retval_SAVE = retval
print_array(retval_SAVE)

// Loop

console.log("Looping...")
M = 1000000
call_rosie = true
for (var i=0; i<5*M; i++) {
//for (var i=0; i<5; i++) {
    if (call_rosie) retval = Rosie.rosie_api("match", eid_CString.ref(), foo.ref())
    else {
	retval = new MyCStringArray;
	retval.n = retval_SAVE.n;
	retval.ptr = retval_SAVE.ptr;
    }
    code = extract_string_from_array(retval, 0)
    if (code != "true") console.log("Error code returned from match api")
    json_string = extract_string_from_array(retval, 1)
    if (call_rosie) Rosie.free_stringArray(retval)
//    if (code=="true") console.log("Successful call to match")
//    else console.log("Call to match FAILED")
//    console.log(json_string)
    obj_to_return_to_caller = JSON.parse(json_string)
}
console.log("Done.\n")