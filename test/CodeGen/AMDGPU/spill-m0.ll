; RUN: llc -O0 -amdgpu-spill-sgpr-to-vgpr=1 -march=amdgcn -mattr=+vgpr-spilling -verify-machineinstrs < %s | FileCheck -check-prefix=TOVGPR -check-prefix=GCN %s
; RUN: llc -O0 -amdgpu-spill-sgpr-to-vgpr=1 -amdgpu-spill-sgpr-to-smem=0 -march=amdgcn -mcpu=tonga -mattr=+vgpr-spilling  -verify-machineinstrs < %s | FileCheck -check-prefix=TOVGPR -check-prefix=GCN %s
; RUN: llc -O0 -amdgpu-spill-sgpr-to-vgpr=0 -march=amdgcn -mattr=+vgpr-spilling -verify-machineinstrs < %s | FileCheck -check-prefix=TOVMEM -check-prefix=GCN %s
; RUN: llc -O0 -amdgpu-spill-sgpr-to-vgpr=0 -amdgpu-spill-sgpr-to-smem=0 -march=amdgcn -mcpu=tonga -mattr=+vgpr-spilling -verify-machineinstrs < %s | FileCheck -check-prefix=TOVMEM -check-prefix=GCN %s
; RUN: llc -O0 -amdgpu-spill-sgpr-to-vgpr=0 -amdgpu-spill-sgpr-to-smem=1 -march=amdgcn -mcpu=tonga -mattr=+vgpr-spilling -verify-machineinstrs < %s | FileCheck -check-prefix=TOSMEM -check-prefix=GCN %s

; XXX - Why does it like to use vcc?

; GCN-LABEL: {{^}}spill_m0:
; TOSMEM: s_mov_b32 s84, SCRATCH_RSRC_DWORD0

; GCN-DAG: s_cmp_lg_u32

; TOVGPR-DAG: s_mov_b32 [[M0_COPY:s[0-9]+]], m0
; TOVGPR: v_writelane_b32 [[SPILL_VREG:v[0-9]+]], [[M0_COPY]], 0

; TOVMEM-DAG: s_mov_b32 [[M0_COPY:s[0-9]+]], m0
; TOVMEM-DAG: v_mov_b32_e32 [[SPILL_VREG:v[0-9]+]], [[M0_COPY]]
; TOVMEM: buffer_store_dword [[SPILL_VREG]], off, s{{\[[0-9]+:[0-9]+\]}}, s{{[0-9]+}} ; 4-byte Folded Spill
; TOVMEM: s_waitcnt vmcnt(0)

; TOSMEM-DAG: s_mov_b32 [[M0_COPY:s[0-9]+]], m0
; TOSMEM: s_mov_b32 m0, s3{{$}}
; TOSMEM-NOT: [[M0_COPY]]
; TOSMEM: s_buffer_store_dword [[M0_COPY]], s[84:87], m0 ; 4-byte Folded Spill
; TOSMEM: s_waitcnt lgkmcnt(0)

; GCN: s_cbranch_scc1 [[ENDIF:BB[0-9]+_[0-9]+]]

; GCN: [[ENDIF]]:
; TOVGPR: v_readlane_b32 [[M0_RESTORE:s[0-9]+]], [[SPILL_VREG]], 0
; TOVGPR: s_mov_b32 m0, [[M0_RESTORE]]

; TOVMEM: buffer_load_dword [[RELOAD_VREG:v[0-9]+]], off, s{{\[[0-9]+:[0-9]+\]}}, s{{[0-9]+}} ; 4-byte Folded Reload
; TOVMEM: s_waitcnt vmcnt(0)
; TOVMEM: v_readfirstlane_b32 [[M0_RESTORE:s[0-9]+]], [[RELOAD_VREG]]
; TOVMEM: s_mov_b32 m0, [[M0_RESTORE]]

; TOSMEM: s_mov_b32 m0, s3{{$}}
; TOSMEM: s_buffer_load_dword [[M0_RESTORE:s[0-9]+]], s[84:87], m0 ; 4-byte Folded Reload
; TOSMEM-NOT: [[M0_RESTORE]]
; TOSMEM: s_mov_b32 m0, [[M0_RESTORE]]

; GCN: s_add_i32 s{{[0-9]+}}, m0, 1
define void @spill_m0(i32 %cond, i32 addrspace(1)* %out) #0 {
entry:
  %m0 = call i32 asm sideeffect "s_mov_b32 m0, 0", "={M0}"() #0
  %cmp0 = icmp eq i32 %cond, 0
  br i1 %cmp0, label %if, label %endif

if:
  call void asm sideeffect "v_nop", ""() #0
  br label %endif

endif:
  %foo = call i32 asm sideeffect "s_add_i32 $0, $1, 1", "=s,{M0}"(i32 %m0) #0
  store i32 %foo, i32 addrspace(1)* %out
  ret void
}

@lds = internal addrspace(3) global [64 x float] undef

; GCN-LABEL: {{^}}spill_m0_lds:
; GCN: s_mov_b32 m0, s6
; GCN: v_interp_mov_f32

; TOSMEM: s_mov_b32 vcc_hi, m0
; TOSMEM: s_mov_b32 m0, s7
; TOSMEM-NEXT: s_buffer_store_dword s{{[0-9]+}}, s{{\[[0-9]+:[0-9]+\]}}, m0 ; 4-byte Folded Spill
; TOSMEM: s_mov_b32 m0, vcc_hi

; TOSMEM: s_mov_b32 vcc_hi, m0
; TOSMEM: s_add_u32 m0, s7, 0x100
; TOSMEM: s_buffer_store_dword s{{[0-9]+}}, s{{\[[0-9]+:[0-9]+\]}}, m0 ; 4-byte Folded Spill
; TOSMEM: s_add_u32 m0, s7, 0x200
; TOSMEM: s_buffer_store_dword s{{[0-9]+}}, s{{\[[0-9]+:[0-9]+\]}}, m0 ; 4-byte Folded Spill
; TOSMEM: s_mov_b32 m0, vcc_hi

; TOSMEM: s_mov_b64 exec,
; TOSMEM: s_cbranch_execz
; TOSMEM: s_branch

; TOSMEM: BB{{[0-9]+_[0-9]+}}:
; TOSMEM-NEXT: s_add_u32 m0, s7, 0x100
; TOSMEM-NEXT: s_buffer_load_dword s{{[0-9]+}}, s{{\[[0-9]+:[0-9]+\]}}, m0 ; 4-byte Folded Reload


; GCN-NOT: v_readlane_b32 m0
; GCN-NOT: s_buffer_store_dword m0
; GCN-NOT: s_buffer_load_dword m0
define amdgpu_ps void @spill_m0_lds(<16 x i8> addrspace(2)* inreg, <16 x i8> addrspace(2)* inreg, <32 x i8> addrspace(2)* inreg, i32 inreg) #0 {
main_body:
  %4 = call float @llvm.SI.fs.constant(i32 0, i32 0, i32 %3)
  %cmp = fcmp ueq float 0.0, %4
  br i1 %cmp, label %if, label %else

if:
  %lds_ptr = getelementptr [64 x float], [64 x float] addrspace(3)* @lds, i32 0, i32 0
  %lds_data = load float, float addrspace(3)* %lds_ptr
  br label %endif

else:
  %interp = call float @llvm.SI.fs.constant(i32 0, i32 0, i32 %3)
  br label %endif

endif:
  %export = phi float [%lds_data, %if], [%interp, %else]
  %5 = call i32 @llvm.SI.packf16(float %export, float %export)
  %6 = bitcast i32 %5 to float
  call void @llvm.SI.export(i32 15, i32 1, i32 1, i32 0, i32 1, float %6, float %6, float %6, float %6)
  ret void
}

; GCN-LABEL: {{^}}restore_m0_lds:
; TOSMEM: s_cmp_eq_u32
; TOSMEM: s_mov_b32 vcc_hi, m0
; TOSMEM: s_mov_b32 m0, s3
; TOSMEM: s_buffer_store_dword s4, s[84:87], m0 ; 4-byte Folded Spill
; TOSMEM: s_mov_b32 m0, vcc_hi
; TOSMEM: s_cbranch_scc1

; TOSMEM: s_mov_b32 m0, -1

; TOSMEM: s_mov_b32 vcc_hi, m0
; TOSMEM: s_mov_b32 m0, s3
; TOSMEM: s_buffer_load_dword s4, s[84:87], m0 ; 4-byte Folded Reload
; TOSMEM: s_add_u32 m0, s3, 0x100
; TOSMEM: s_waitcnt lgkmcnt(0)
; TOSMEM: s_buffer_load_dword s5, s[84:87], m0 ; 4-byte Folded Reload
; TOSMEM: s_mov_b32 m0, vcc_hi
; TOSMEM: s_waitcnt lgkmcnt(0)

; TOSMEM: ds_write_b64

; TOSMEM: s_mov_b32 vcc_hi, m0
; TOSMEM: s_add_u32 m0, s3, 0x200
; TOSMEM: s_buffer_load_dword s0, s[84:87], m0 ; 4-byte Folded Reload
; TOSMEM: s_mov_b32 m0, vcc_hi
; TOSMEM: s_waitcnt lgkmcnt(0)
; TOSMEM: s_mov_b32 m0, s0
; TOSMEM: ; use m0

; TOSMEM: s_dcache_wb
; TOSMEM: s_endpgm
define void @restore_m0_lds(i32 %arg) {
  %m0 = call i32 asm sideeffect "s_mov_b32 m0, 0", "={M0}"() #0
  %sval = load volatile i64, i64 addrspace(2)* undef
  %cmp = icmp eq i32 %arg, 0
  br i1 %cmp, label %ret, label %bb

bb:
  store volatile i64 %sval, i64 addrspace(3)* undef
  call void asm sideeffect "; use $0", "{M0}"(i32 %m0) #0
  br label %ret

ret:
  ret void
}

declare float @llvm.SI.fs.constant(i32, i32, i32) readnone

declare i32 @llvm.SI.packf16(float, float) readnone

declare void @llvm.SI.export(i32, i32, i32, i32, i32, float, float, float, float)

attributes #0 = { nounwind }
