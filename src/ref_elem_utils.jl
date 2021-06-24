#####
##### ordering of faces in terms of vertices
#####
function face_vertices(elem::Line)
    return 1,2
end

function find_face_nodes(elem::Tri,r,s,tol=50*eps())
    e1 = findall(@. abs(s+1)<tol)
    e2 = findall(@. abs(r+s)<tol)
    e3 = findall(@. abs(r+1)<tol)
    return e1,reverse(e2),reverse(e3)
end

function find_face_nodes(elem::Quad,r,s,tol=50*eps())
    e1 = findall(@. abs(s+1)<tol)
    e2 = findall(@. abs(r-1)<tol)
    e3 = findall(@. abs(s-1)<tol)
    e4 = findall(@. abs(r+1)<tol)
    return e1,e2,reverse(e3),reverse(e4)
end

function find_face_nodes(elem::Hex,r,s,t,tol=50*eps())
    fv1 = findall(@. abs(r+1) < tol)
    fv2 = findall(@. abs(r-1) < tol)
    fv3 = findall(@. abs(s+1) < tol)
    fv4 = findall(@. abs(s-1) < tol)
    fv5 = findall(@. abs(t+1) < tol)
    fv6 = findall(@. abs(t-1) < tol)
    return fv1,fv2,fv3,fv4,fv5,fv6
end

function find_face_nodes(elem::Tet,r,s,t,tol=50*eps())
    fv1 = findall(@. abs(s+1) < tol)
    fv2 = findall(@. abs(r+s+t+1) < tol)
    fv3 = findall(@. abs(r+1) < tol)
    fv4 = findall(@. abs(t+1) < tol)
    return fv1,fv2,fv3,fv4
end

# face vertices = face nodes of degree 1
face_vertices(elem) = find_face_nodes(elem,nodes(elem,1)...)

#####
##### face data for diff elements
#####

function map_face_nodes(elem::Tri, face_nodes)
    r1D = face_nodes
    e = ones(size(r1D)) # vector of all ones
    rf = [r1D; -r1D; -e];
    sf = [-e; r1D; -r1D];
    return rf,sf
end
function map_face_nodes(elem::Quad, face_nodes)
    r1D = face_nodes
    e = ones(size(r1D))
    rf = [r1D; e; -r1D; -e]
    sf = [-e; r1D; e; -r1D]
    return rf,sf
end
function map_face_nodes(elem::Hex, face_nodes...)
    r,s = face_nodes
    e = ones(size(r))
    rf = [-e; e; r; r; r; r]
    sf = [r; r; -e; e; s; s]
    tf = [s; s; s; s; -e; e]
    return rf,sf,tf
end
function map_face_nodes(elem::Tet, face_nodes...)
    r,s = face_nodes
    e = ones(size(r))
    rf = [r; r; -e; r]
    sf = [-e; s; r; s]
    tf = [s; -(e + r + s); s; -e]
    return rf,sf,tf
end

# for dispatching 
face_type(::Union{Tri,Quad}) = Line()
face_type(::Hex) = Quad()
face_type(::Tet) = Tri()

"""
    function inverse_trace_constant(rd::RefElemData)

Returns the degree-dependent constant in the inverse trace equality over the reference element (as 
reported in ["GPU-accelerated dG methods on hybrid meshes"](https://doi.org/10.1016/j.jcp.2016.04.003)
by Chan, Wang, Modave, Remacle, Warburton 2016). 

Can be used to estimate dependence of maximum stable timestep on degree of approximation. 
"""
inverse_trace_constant(rd::RefElemData{1}) = (rd.N+1)*(rd.N+2)/2
inverse_trace_constant(rd::RefElemData{2,Quad}) = (rd.N+1)*(rd.N+2)
inverse_trace_constant(rd::RefElemData{3,Hex}) = 3*(rd.N+1)*(rd.N+2)/2
inverse_trace_constant(rd::RefElemData{1,Line,SBP}) = rd.N*(rd.N+1)/2 # assumes SBP <=> DGSEM
inverse_trace_constant(rd::RefElemData{2,Quad,SBP}) = rd.N*(rd.N+1) # assumes SBP <=> DGSEM
inverse_trace_constant(rd::RefElemData{3,Hex,SBP}) = 3*rd.N*(rd.N+1)/2 # assumes SBP <=> DGSEM

# precomputed
_inverse_trace_constants(rd::RefElemData{2,Tri,Polynomial}) = (6.0, 10.898979485566365, 16.292060161853993, 23.999999999999808, 31.884512140579055, 42.42373503225737, 52.88579066878113, 66.25284319164409, 79.3535377715693, 95.53911875636945)
_inverse_trace_constants(rd::RefElemData{3,Tet,Polynomial}) = (10.,16.892024376045097,23.58210016200093,33.828424659883034,43.40423356477473,56.98869932201791,69.68035962892684)
inverse_trace_constant(rd::RefElemData{2,Tri,Polynomial}) where {Dim} = _inverse_trace_constants(rd)[rd.N]
inverse_trace_constant(rd::RefElemData{3,Tet,Polynomial}) where {Dim} = _inverse_trace_constants(rd)[rd.N]

# generic fallback
function inverse_trace_constant(rd::RefElemData)
    return maximum(eigvals(Matrix(rd.Vf'*diagm(rd.wf)*rd.Vf),Matrix(rd.M)))
end
