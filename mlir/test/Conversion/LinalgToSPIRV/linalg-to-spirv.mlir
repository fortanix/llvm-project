// RUN: mlir-opt -split-input-file -convert-linalg-to-spirv -canonicalize -verify-diagnostics %s -o - | FileCheck %s

//===----------------------------------------------------------------------===//
// Single workgroup reduction
//===----------------------------------------------------------------------===//

#single_workgroup_reduction_trait = {
  args_in = 1,
  args_out = 1,
  iterator_types = ["reduction"],
  indexing_maps = [
    affine_map<(i) -> (i)>,
    affine_map<(i) -> (0)>
  ]
}

module attributes {
  spv.target_env = {
    version = 3 : i32,
    extensions = [],
    capabilities = [1: i32, 63: i32] // Shader, GroupNonUniformArithmetic
  }
} {

// CHECK:      spv.globalVariable
// CHECK-SAME: built_in("LocalInvocationId")

// CHECK:      func @single_workgroup_reduction
// CHECK-SAME: (%[[INPUT:.+]]: !spv.ptr{{.+}}, %[[OUTPUT:.+]]: !spv.ptr{{.+}})

// CHECK:        %[[ZERO:.+]] = spv.constant 0 : i32
// CHECK:        %[[ID:.+]] = spv.Load "Input" %{{.+}} : vector<3xi32>
// CHECK:        %[[X:.+]] = spv.CompositeExtract %[[ID]][0 : i32]

// CHECK:        %[[INPTR:.+]] = spv.AccessChain %[[INPUT]][%[[ZERO]], %[[X]]]
// CHECK:        %[[VAL:.+]] = spv.Load "StorageBuffer" %[[INPTR]] : i32
// CHECK:        %[[ADD:.+]] = spv.GroupNonUniformIAdd "Subgroup" "Reduce" %[[VAL]] : i32

// CHECK:        %[[OUTPTR:.+]] = spv.AccessChain %[[OUTPUT]][%[[ZERO]], %[[ZERO]]]
// CHECK:        %[[ELECT:.+]] = spv.GroupNonUniformElect "Subgroup" : i1

// CHECK:        spv.selection {
// CHECK:          spv.BranchConditional %[[ELECT]], ^bb1, ^bb2
// CHECK:        ^bb1:
// CHECK:          spv.AtomicIAdd "Device" "AcquireRelease" %[[OUTPTR]], %[[ADD]]
// CHECK:          spv.Branch ^bb2
// CHECK:        ^bb2:
// CHECK:          spv._merge
// CHECK:        }
// CHECK:        spv.Return

func @single_workgroup_reduction(%input: memref<16xi32>, %output: memref<1xi32>) attributes {
  spv.entry_point_abi = {local_size = dense<[16, 1, 1]>: vector<3xi32>}
} {
  linalg.generic #single_workgroup_reduction_trait %input, %output {
    ^bb(%in: i32, %out: i32):
      %sum = addi %in, %out : i32
      linalg.yield %sum : i32
  } : memref<16xi32>, memref<1xi32>
  spv.Return
}
}

// -----

// Missing shader entry point ABI

#single_workgroup_reduction_trait = {
  args_in = 1,
  args_out = 1,
  iterator_types = ["reduction"],
  indexing_maps = [
    affine_map<(i) -> (i)>,
    affine_map<(i) -> (0)>
  ]
}

module attributes {
  spv.target_env = {
    version = 3 : i32,
    extensions = [],
    capabilities = [1: i32, 63: i32] // Shader, GroupNonUniformArithmetic
  }
} {
func @single_workgroup_reduction(%input: memref<16xi32>, %output: memref<1xi32>) {
  // expected-error @+1 {{failed to legalize operation 'linalg.generic'}}
  linalg.generic #single_workgroup_reduction_trait %input, %output {
    ^bb(%in: i32, %out: i32):
      %sum = addi %in, %out : i32
      linalg.yield %sum : i32
  } : memref<16xi32>, memref<1xi32>
  return
}
}

// -----

// Mismatch between shader entry point ABI and input memref shape

#single_workgroup_reduction_trait = {
  args_in = 1,
  args_out = 1,
  iterator_types = ["reduction"],
  indexing_maps = [
    affine_map<(i) -> (i)>,
    affine_map<(i) -> (0)>
  ]
}

module attributes {
  spv.target_env = {
    version = 3 : i32,
    extensions = [],
    capabilities = [1: i32, 63: i32] // Shader, GroupNonUniformArithmetic
  }
} {
func @single_workgroup_reduction(%input: memref<16xi32>, %output: memref<1xi32>) attributes {
  spv.entry_point_abi = {local_size = dense<[32, 1, 1]>: vector<3xi32>}
} {
  // expected-error @+1 {{failed to legalize operation 'linalg.generic'}}
  linalg.generic #single_workgroup_reduction_trait %input, %output {
    ^bb(%in: i32, %out: i32):
      %sum = addi %in, %out : i32
      linalg.yield %sum : i32
  } : memref<16xi32>, memref<1xi32>
  spv.Return
}
}

// -----

// Unsupported multi-dimension input memref

#single_workgroup_reduction_trait = {
  args_in = 1,
  args_out = 1,
  iterator_types = ["parallel", "reduction"],
  indexing_maps = [
    affine_map<(i, j) -> (i, j)>,
    affine_map<(i, j) -> (i)>
  ]
}

module attributes {
  spv.target_env = {
    version = 3 : i32,
    extensions = [],
    capabilities = [1: i32, 63: i32] // Shader, GroupNonUniformArithmetic
  }
} {
func @single_workgroup_reduction(%input: memref<16x8xi32>, %output: memref<16xi32>) attributes {
  spv.entry_point_abi = {local_size = dense<[16, 8, 1]>: vector<3xi32>}
} {
  // expected-error @+1 {{failed to legalize operation 'linalg.generic'}}
  linalg.generic #single_workgroup_reduction_trait %input, %output {
    ^bb(%in: i32, %out: i32):
      %sum = addi %in, %out : i32
      linalg.yield %sum : i32
  } : memref<16x8xi32>, memref<16xi32>
  spv.Return
}
}