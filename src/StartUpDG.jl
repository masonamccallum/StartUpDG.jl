"""
Module StartUpDG

Module to aid in setting up reference operators, meshes, and geometric terms
"""

module StartUpDG

using LinearAlgebra # for diagm, identity matrix I
using NodesAndModes # for basis functions
using StaticArrays  # for SMatrix
using Setfield      # for "modifying" structs to modify node mappings
using UnPack        # for getting values in RefElemData and MeshData

import NodesAndModes: meshgrid
import SparseArrays: sparse, droptol!
import UnPack: @unpack

export Line, Tri, Quad, Hex # element types from NodesAndModes
export @unpack

# reference element utility functions
export RefElemData
include("RefElemData.jl")
include("ref_elem_utils.jl")

export MeshData, MeshData!
include("MeshData.jl")

# ref-to-physical geometric terms
export geometric_factors
include("geometric_mapping_functions.jl")

# spatial connectivity routines
export make_nodemaps_periodic!
include("connectivity_functions.jl")

# uniform meshes + face vertex orderings are included
export readGmsh2D, uniform_mesh
include("simple_meshes.jl")

# simple explicit time-stepping included for conveniencea
export ck45, dp56, PIparams, compute_adaptive_dt # LSERK 45 + Dormand-Prince 56
include("explicit_timestep_utils.jl")

end
