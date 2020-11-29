// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module pref

import os
import v.vcache

pub const (
	default_module_path = os.vmodules_dir()
)

pub fn new_preferences() Preferences {
	mut p := Preferences{}
	p.fill_with_defaults()
	return p
}

pub fn (mut p Preferences) fill_with_defaults() {
	if p.vroot == '' {
		// Location of all vlib files
		p.vroot = os.dir(vexe_path())
	}
	vlib_path := os.join_path(p.vroot, 'vlib')
	if p.lookup_path.len == 0 {
		p.lookup_path = ['@vlib', '@vmodules']
	}
	for i, path in p.lookup_path {
		p.lookup_path[i] = path.replace('@vlib', vlib_path).replace('@vmodules', default_module_path)
	}
	rpath := os.real_path(p.path)
	if p.out_name == '' {
		filename := os.file_name(rpath).trim_space()
		mut base := filename.all_before_last('.')
		if base == '' {
			// The file name is just `.v` or `.vsh` or `.*`
			base = filename
		}
		target_dir := if os.is_dir(rpath) { rpath } else { os.dir(rpath) }
		p.out_name = os.join_path(target_dir, base)
		if rpath == '$p.vroot/cmd/v' && os.is_dir('vlib/compiler') {
			// Building V? Use v2, since we can't overwrite a running
			// executable on Windows + the precompiled V is more
			// optimized.
			println('Saving the resulting V executable in `./v2`')
			println('Use `v -o v cmd/v` if you want to replace current ' + 'V executable.')
			p.out_name = 'v2'
		}
	}
	rpath_name := os.file_name(rpath)
	p.building_v = !p.is_repl && (rpath_name == 'v' || rpath_name == 'vfmt.v')
	if p.os == ._auto {
		// No OS specifed? Use current system
		p.os = get_host_os()
	}
	//
	p.try_to_use_tcc_by_default()
	if p.ccompiler == '' {
		p.ccompiler = default_c_compiler()
	}
	p.ccompiler_type = cc_from_string(p.ccompiler)
	p.is_test = p.path.ends_with('_test.v')
	p.is_vsh = p.path.ends_with('.vsh')
	p.is_script = p.is_vsh || p.path.ends_with('.v') || p.path.ends_with('.vv')
	if p.third_party_option == '' {
		p.third_party_option = p.cflags
		$if !windows {
			if !p.third_party_option.contains('-fPIC') {
				p.third_party_option += ' -fPIC'
			}
		}
	}
	// Prepare the cache manager. All options that can affect the generated cached .c files
	// should go into res.cache_manager.vopts, which is used as a salt for the cache hash.
	p.cache_manager = vcache.new_cache_manager([
		@VHASH,
		/* ensure that different v versions use separate build artefacts */
		'$p.backend | $p.os | $p.ccompiler',
		p.cflags.trim_space(),
		p.third_party_option.trim_space(),
		'$p.compile_defines_all',
		'$p.compile_defines',
		'$p.lookup_path',
	])
	// eprintln('prefs.cache_manager: $p')
}

fn (mut p Preferences) try_to_use_tcc_by_default() {
	if p.ccompiler == 'tcc' {
		p.ccompiler = default_tcc_compiler()
		return
	}
	if p.ccompiler == '' {
		// tcc is known to fail several tests on macos, so do not
		// try to use it by default, only when it is explicitly set
		$if macos {
			return
		}
		p.ccompiler = default_tcc_compiler()
		return
	}
}

pub fn default_tcc_compiler() string {
	vexe := vexe_path()
	vroot := os.dir(vexe)
	vtccexe := os.join_path(vroot, 'thirdparty', 'tcc', 'tcc.exe')
	if os.exists(vtccexe) {
		return vtccexe
	}
	return ''
}

pub fn default_c_compiler() string {
	// fast_clang := '/usr/local/Cellar/llvm/8.0.0/bin/clang'
	// if os.exists(fast_clang) {
	// return fast_clang
	// }
	// TODO fix $if after 'string'
	$if windows {
		return 'gcc'
	}
	return 'cc'
}

pub fn vexe_path() string {
	vexe := os.getenv('VEXE')
	if vexe != '' {
		return vexe
	}
	real_vexe_path := os.real_path(os.executable())
	os.setenv('VEXE', real_vexe_path, true)
	return real_vexe_path
}
