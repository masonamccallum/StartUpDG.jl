"""
    struct RefElemData

RefElemData: contains info (interpolation points, volume/face quadrature, operators)
for a high order nodal basis on a given reference element. 

Example:
```julia
N = 3
rd = RefElemData(Tri(), N)
@unpack r, s = rd
```
""" 
struct RefElemData{Dim, ElemShape <: AbstractElemShape, ApproximationType, 
                   FV, RST, RSTP, RSTQ, RSTF, NRSTJ, FMASK, TVDM, 
                   VQ, VF, MM, P, D, L, VP, V1Type, WQ, WF} 

    element_type::ElemShape
    approximation_type::ApproximationType # Polynomial / SBP{...}

    N::Int               # polynomial degree of accuracy
    fv::FV               # list of vertices defining faces, e.g., ([1,2],[2,3],[3,1]) for a triangle
    V1::V1Type           # low order interpolation matrix

    rst::RST             # interpolation node coordinates
    VDM::TVDM            # generalized Vandermonde matrix
    Fmask::FMASK         # indices of face nodes

    Nplot::Int           # TODO: remove. Nplot doesn't do anything IIRC...
    rstp::RSTP           # plotting nodes
    Vp::VP               # interpolation matrix to plotting nodes

    # volume quadrature 
    rstq::RSTQ
    wq::WQ
    Vq::VQ               # quad interp mat

    # face quadrature 
    rstf::RSTF
    wf::WF               # quad weights
    Vf::VF               # face quad interp mat
    nrstJ::NRSTJ         # reference normals, quad weights

    M::MM                # mass matrix
    Pq::P                # L2 projection matrix

    # Nodal DG operators
    Drst::NTuple{Dim, D} # differentiation operators
    LIFT::L              # lift matrix
end

# need this to use @set outside of StartUpDG
function ConstructionBase.setproperties(rd::RefElemData, patch::NamedTuple)
    fields = (haskey(patch, symbol) ? getproperty(patch, symbol) : getproperty(rd, symbol) for symbol in fieldnames(typeof(rd)))         
    return RefElemData(fields...)
end

ConstructionBase.getproperties(rd::RefElemData) = 
    (; elementType=rd.elementType, approximation_type=rd.approximation_type, N=rd.N, fv=rd.fv, V1=rd.V1, 
       rst=rd.rst, VDM=rd.VDM, Fmask=rd.Fmask, Nplot=rd.Nplot, rstp=rd.rstp, Vp=rd.Vp, 
       rstq=rd.rstq, wq=rd.wq, Vq=rd.Vq, rstf=rd.rstf, wf=rd.wf, Vf=rd.Vf, nrstJ=rd.nrstJ, 
       M=rd.M, Pq=rd.Pq, Drst=rd.Drst, LIFT=rd.LIFT)

function Base.show(io::IO, ::MIME"text/plain", rd::RefElemData)
    @nospecialize rd
    print(io,"RefElemData for a degree $(rd.N) $(rd.approximation_type) approximation on $(rd.elementType) element.")
end

function Base.show(io::IO, rd::RefElemData)
    @nospecialize basis # reduce precompilation time
    print(io,"RefElemData{N=$(rd.N),$(rd.approximation_type),$(rd.elementType)}.")
end

_propertynames(::Type{RefElemData}, private::Bool = false) = (:Nfaces, :Np, :Nq, :Nfq)
function Base.propertynames(x::RefElemData{1}, private::Bool=false) 
    return (fieldnames(RefElemData)..., _propertynames(RefElemData)...,
            :r, :rq, :rf, :rp, :nrJ, :Dr)
end
function Base.propertynames(x::RefElemData{2}, private::Bool = false)
    return (fieldnames(RefElemData)..., _propertynames(RefElemData)...,
            :r, :s, :rq, :sq, :rf, :sf, :rp, :sp, :nrJ, :nsJ, :Dr, :Ds)
end
function Base.propertynames(x::RefElemData{3}, private::Bool = false)
    return (fieldnames(RefElemData)..., _propertynames(RefElemData)...,
            :r, :s, :t, :rq, :sq, :tq, :rf, :sf, :tf, 
            :rp, :sp, :tp, :nrJ, :nsJ, :ntJ, :Dr, :Ds, :Dt)
end

# convenience unpacking routines
function Base.getproperty(x::RefElemData{Dim, ElementType, ApproxType}, s::Symbol) where {Dim, ElementType, ApproxType}
    if s==:r
        return getfield(x, :rst)[1]
    elseif s==:s
        return getfield(x, :rst)[2]
    elseif s==:t
        return getfield(x, :rst)[3]

    elseif s==:rq
        return getfield(x, :rstq)[1]
    elseif s==:sq
        return getfield(x, :rstq)[2]
    elseif s==:tq
        return getfield(x, :rstq)[3]

    elseif s==:rf
        return getfield(x, :rstf)[1]
    elseif s==:sf
        return getfield(x, :rstf)[2]
    elseif s==:tf
        return getfield(x, :rstf)[3]

    elseif s==:rp
        return getfield(x, :rstp)[1]
    elseif s==:sp
        return getfield(x, :rstp)[2]
    elseif s==:tp
        return getfield(x, :rstp)[3]

    elseif s==:nrJ
        return getfield(x, :nrstJ)[1]
    elseif s==:nsJ
        return getfield(x, :nrstJ)[2]
    elseif s==:ntJ
        return getfield(x, :nrstJ)[3]

    elseif s==:Dr
        return getfield(x, :Drst)[1]
    elseif s==:Ds
        return getfield(x, :Drst)[2]
    elseif s==:Dt
        return getfield(x, :Drst)[3]
        
    elseif s==:Nfaces || s==:num_faces
        return num_faces(x.element_type)
    elseif s==:Np
        return length(getfield(x, :rst)[1])
    elseif s==:Nq
        return length(getfield(x, :rstq)[1])
    elseif s==:Nfq
        return length(getfield(x, :rstf)[1])

    # CamlCase will be deprecated in a future release
    elseif s==:elemShape || s==:elementType 
        return getfield(x, :element_type)
    elseif s==:approximationType
        return getfield(x, :approximation_type)
    else
        return getfield(x, s)
    end
end

"""
    function RefElemData(elem; N, kwargs...)
    function RefElemData(elem, approxType; N, kwargs...)

Keyword argument constructor for RefElemData (to "label" `N` via `rd = RefElemData(Line(), N=3)`)
"""
RefElemData(elem; N, kwargs...) = RefElemData(elem, N; kwargs...)
RefElemData(elem, approxType; N, kwargs...) = RefElemData(elem, approxType, N; kwargs...)

# default to Polynomial-type RefElemData
RefElemData(elem, N::Int; kwargs...) = RefElemData(elem, Polynomial(), N; kwargs...)


@inline Base.ndims(::Line) = 1
@inline Base.ndims(::Union{Tri,Quad}) = 2
@inline Base.ndims(::Union{Tet,Hex}) = 3

@inline num_vertices(::Tri) = 3
@inline num_vertices(::Union{Quad, Tet}) = 4
@inline num_vertices(::Hex) = 8
@inline num_vertices(::Wedge) = 6
@inline num_vertices(::Pyr) = 5

@inline num_faces(::Line) = 2
@inline num_faces(::Tri) = 3
@inline num_faces(::Union{Quad, Tet}) = 4
@inline num_faces(::Union{Wedge, Pyr}) = 5
@inline num_faces(::Hex) = 6

@inline face_type(::Union{Tri, Quad}) = Line()
@inline face_type(::Hex) = Quad()
@inline face_type(::Tet) = Tri()

# ====================================================
#          RefElemData approximation types
# ====================================================

struct Polynomial end 

# ========= SBP approximation types ============

struct DefaultSBPType end

# line/quad/hex nodes
struct TensorProductLobatto end

# triangle node types
struct Hicken end 
struct Kubatko{FaceNodeType} end

# face node types for Kubatko
struct LegendreFaceNodes end
struct LobattoFaceNodes end

# SBP approximation type: the more common diagonal E and diagonal-norm SBP operators on tri/quads.
struct SBP{Type}
    SBP() = new{DefaultSBPType}() # no-parameter default
    SBP{T}() where {T} = new{T}()  # default constructor
end 

# sets default to TensorProductLobatto on Quads 
RefElemData(elem::Union{Line, Quad, Hex}, approxT::SBP{DefaultSBPType}, N) = RefElemData(elem, SBP{TensorProductLobatto}(), N)

# sets default to Kubatko{LobattoFaceNodes} on Tris
RefElemData(elem::Tri, approxT::SBP{DefaultSBPType}, N) = RefElemData(elem, SBP{Kubatko{LobattoFaceNodes}}(), N)

