# used to identify the mesh type
struct CutCellMesh end

# maps x ∈ [-1,1] to [a,b]
map_to_interval(x, a, b) = a + (b-a) * 0.5 * (1 + x)

function count_cut_faces(cutcells)
    num_cut_faces = zeros(Int, length(cutcells))
    for e in eachindex(cutcells)
        curve = cutcells[e]
        stop_points = curve.stop_pts        
        num_cut_faces[e] = length(stop_points) - 1
    end
    return num_cut_faces
end

function neighbor_across_face(f, ex, ey)
    if f==1
        return (ex-1, ey)
    elseif f==2
        return (ex+1, ey)
    elseif f==3
        return (ex, ey-1)
    elseif f==4
        return (ex, ey+1)
    else
        error("Face index f = $f > 4; too large.")
    end
end

function compute_face_centroids(rd, xf, yf, cutcell_data)

    @unpack region_flags, cut_faces_per_cell, cut_face_offsets = cutcell_data
    num_cut_cells = length(cut_faces_per_cell)
    num_cartesian_cells = sum(region_flags .== 0)
    num_cut_faces = sum(cut_faces_per_cell)

    num_points_per_face = length(rd.rf) ÷ num_faces(rd.element_type)
    
    face_centroids_x = ComponentArray(cartesian=zeros(num_faces(rd.element_type), num_cartesian_cells), 
                                      cut=zeros(num_cut_faces))
    face_centroids_y = similar(face_centroids_x)

    for e in 1:num_cartesian_cells
        xf_element = reshape(view(xf.cartesian, :, e), num_points_per_face, num_faces(rd.element_type))
        yf_element = reshape(view(yf.cartesian, :, e), num_points_per_face, num_faces(rd.element_type))
        view(face_centroids_x.cartesian, :, e) .= vec(sum(xf_element, dims=1) / num_points_per_face)
        view(face_centroids_y.cartesian, :, e) .= vec(sum(yf_element, dims=1) / num_points_per_face)
    end

    for e in 1:num_cut_cells    
        face_node_ids = (1:(num_points_per_face * cut_faces_per_cell[e])) .+ cut_face_offsets[e] * num_points_per_face
        xf_element = reshape(view(xf.cut, face_node_ids), num_points_per_face, cut_faces_per_cell[e])
        yf_element = reshape(view(yf.cut, face_node_ids), num_points_per_face, cut_faces_per_cell[e])

        face_ids = (1:cut_faces_per_cell[e]) .+ cut_face_offsets[e]
        view(face_centroids_x.cut, face_ids) .= vec(sum(xf_element, dims=1) / num_points_per_face)
        view(face_centroids_y.cut, face_ids) .= vec(sum(yf_element, dims=1) / num_points_per_face)
    end

    return face_centroids_x, face_centroids_y
end

function compute_element_indices(region_flags)

    cells_per_dimension_x, cells_per_dimension_y = size(region_flags)
   
    element_indices = fill!(similar(region_flags), zero(eltype(region_flags)))

    # count Cartesian elements
    e = 1
    for ex in 1:cells_per_dimension_x, ey in 1:cells_per_dimension_y    
        if is_Cartesian(region_flags[ex, ey])
            element_indices[ex, ey] = e
            e += 1
        end
    end

    # reset counter for cut cells
    e = 1
    for ex in 1:cells_per_dimension_x, ey in 1:cells_per_dimension_y    
        if is_cut(region_flags[ex, ey])
            element_indices[ex, ey] = e
            e += 1
        end
    end

    return element_indices
end

function is_inside_domain(ex, ey, regions) 
    num_cells_x, num_cells_y = size(regions)
    inside_cartesian_domain = (0 < ex <= num_cells_x) & (0 < ey <= num_cells_y) 
    if inside_cartesian_domain 
        # check if a cell is also inside the cut geometry
        return inside_cartesian_domain & (regions[ex, ey] >= 0) 
    else
        return false
    end
end

# Computes face geometric terms from a RefElemData, `quad_rule_face = (r1D, w1D)`, 
# the vectors of the 1D vertex nodes `vx` and `vy`, and named tuple 
# `cutcell_data is a NamedTuple containing `region_flags`, `stop_pts``, `cutcells`. 
function compute_geometric_data(rd::RefElemData{2, Quad}, quad_rule_face, 
                                vx, vy, cutcell_data; tol=100 * eps())

    # domain size and reference face weights
    cells_per_dimension_x, cells_per_dimension_y = length(vx) - 1, length(vy) - 1
    LX, LY = (x -> x[2] - x[1]).(extrema.((vx, vy)))

    r1D, w1D = quad_rule_face

    @unpack region_flags, stop_pts, cutcells, cut_faces_per_cell = cutcell_data

    # count number of cells and cut face nodes
    num_cartesian_cells = sum(region_flags .== 0)
    num_cut_cells = sum(region_flags .== 1) 
    nodes_per_face = length(r1D)
    num_cut_face_nodes = nodes_per_face * sum(cut_faces_per_cell)

    x, y, J = ntuple(_ -> ComponentArray(cartesian=zeros(rd.Np, num_cartesian_cells), 
                                         cut=zeros(Np_cut(rd.N), num_cut_cells)), 3)

    rxJ, sxJ, ryJ, syJ = ntuple(_ -> ComponentArray(cartesian=zeros(rd.Np, num_cartesian_cells), 
                                                    cut=zeros(Np_cut(rd.N), num_cut_cells)), 4)

    xf, yf, nxJ, nyJ, Jf = 
        ntuple(_ -> ComponentArray(cartesian=zeros(rd.Nfq, num_cartesian_cells), 
                                cut=zeros(num_cut_face_nodes)), 5)

    # 3) compute Cartesian face points and geometric factors
    face_ids_left_right = 1:(length(rd.rf) ÷ 2)
    face_ids_top_bottom = ((length(rd.rf) ÷ 2) + 1):length(rd.rf)

    # the face Jacobian involves scaling between mapped and reference domain
    rxJ.cartesian .= LX / (2 * cells_per_dimension_x)
    sxJ.cartesian .= LY / (2 * cells_per_dimension_y)
    J.cartesian .= (LX / cells_per_dimension_x) * (LY / cells_per_dimension_y) / 4 # 4 = reference volume
    Jf.cartesian[face_ids_top_bottom, :] .= LX / (cells_per_dimension_x * sum(w1D))
    Jf.cartesian[face_ids_left_right, :] .= LY / (cells_per_dimension_y * sum(w1D))

    e = 1
    for ex in 1:cells_per_dimension_x, ey in 1:cells_per_dimension_y    
        if is_Cartesian(region_flags[ex, ey])
            vx_element = SVector(vx[ex], vx[ex + 1], vx[ex], vx[ex + 1])
            vy_element = SVector(vy[ey], vy[ey], vy[ey + 1], vy[ey + 1])
            x_element, y_element = map(x -> rd.V1 * x, (vx_element, vy_element))
            view(x.cartesian, :, e) .= x_element
            view(y.cartesian, :, e) .= y_element
            mul!(view(xf.cartesian, :, e), rd.Vf, x_element)
            mul!(view(yf.cartesian, :, e), rd.Vf, y_element)
            view(nxJ.cartesian, :, e) .= rd.nrJ .* view(Jf.cartesian, :, e)
            view(nyJ.cartesian, :, e) .= rd.nsJ .* view(Jf.cartesian, :, e)
            e = e + 1
        end
    end        
   
    # 4) compute cut-cell face points
    element_indices = compute_element_indices(region_flags)
    physical_frame_elements = PhysicalFrame[] # populate this as we iterate through cut cells

    # The volume Jacobian for cut elements is 1 since the "reference element" 
    # is the cut element itself. 
    fill!(J.cut, one(eltype(J)))

    e = 1
    fid = 1
    for ex in 1:cells_per_dimension_x, ey in 1:cells_per_dimension_y    
        if is_cut(region_flags[ex, ey])

            curve = cutcells[e]
            stop_points = curve.stop_pts

            for f in 1:length(stop_points)-1
                for i in eachindex(r1D)
                    s = map_to_interval(r1D[i], stop_points[f], stop_points[f+1])

                    x_node, y_node = curve(s)                
                    xf.cut[fid], yf.cut[fid] = x_node, y_node

                    tangent_vector = PathIntersections.ForwardDiff.derivative(curve, s)
                    normal_node = SVector{2}(tangent_vector[2], -tangent_vector[1])
                    nxJ.cut[fid], nyJ.cut[fid] = -normal_node # flip sign for outward normal

                    # Jacobian involves scaling between mapped and reference domain
                    scaling = (stop_points[f+1] - stop_points[f]) / sum(w1D)
                    Jf.cut[fid] = norm(tangent_vector) * scaling

                    fid += 1
                end
            end

            # find points inside element
            vx_element = SVector(vx[ex], vx[ex + 1], vx[ex], vx[ex + 1])
            vy_element = SVector(vy[ey], vy[ey], vy[ey + 1], vy[ey + 1])
            x_element, y_element = map(x -> rd.V1 * x, (vx_element, vy_element))

            @unpack curves = cutcell_data
            N_sampled = 3 * rd.N
            r_sampled, s_sampled = equi_nodes(rd.element_type, N_sampled) # oversampled nodes
            V_sampled = vandermonde(rd.element_type, rd.N, r_sampled, s_sampled) / rd.VDM 
            x_sampled, y_sampled = V_sampled * x_element, V_sampled * y_element

            # TODO: fix, only works for a single curve for now
            is_in_element = is_contained.(first(curves), zip(x_sampled, y_sampled)) .== false

            while sum(is_in_element) < Np_cut(rd.N)
                # TODO: fix, only works for a single curve for now
                is_in_element = is_contained.(first(curves), zip(x_sampled, y_sampled)) .== false
                if sum(is_in_element) < Np_cut(rd.N)
                    N_sampled += rd.N
                    r_sampled, s_sampled = equi_nodes(rd.element_type, N_sampled) # oversampled nodes
                    V_sampled = vandermonde(rd.element_type, rd.N, r_sampled, s_sampled) / rd.VDM 
                    x_sampled, y_sampled = V_sampled * x_element, V_sampled * y_element    
                end
            end
               
            # here, we evaluate a PhysicalFrame basis by shifting and scaling the 
            # coordinates on an element back to the reference element [-1, 1]^2.
            @unpack cut_faces_per_cell, cut_face_offsets = cutcell_data
            num_points_per_face = length(r1D)
            cut_face_node_ids = (1:num_points_per_face * cut_faces_per_cell[e]) .+ 
                                num_points_per_face * cut_face_offsets[e]

            physical_frame_element = 
                PhysicalFrame(xf.cut[cut_face_node_ids], yf.cut[cut_face_node_ids])
            push!(physical_frame_elements, physical_frame_element)

            ids_in_element = findall(is_in_element)
            V = vandermonde(physical_frame_element, rd.N, 
                            r_sampled[ids_in_element], 
                            s_sampled[ids_in_element]) 

            # use pivoted QR to find good interpolation points
            QRfac = qr(V', ColumnNorm())
            ids = QRfac.p[1:Np_cut(rd.N)]
            view(x.cut, :, e) .= x_sampled[ids_in_element[ids]]
            view(y.cut, :, e) .= y_sampled[ids_in_element[ids]]

            # geometric terms depend on the shifting and scaling
            view(rxJ.cut, :, e) .= physical_frame_element.scaling[1]
            view(syJ.cut, :, e) .= physical_frame_element.scaling[2]

            e += 1

        end # is_cut
    end

    rstxyzJ = SMatrix{2, 2}(rxJ, sxJ, ryJ, syJ)
    return x, y, rstxyzJ, J, xf, yf, nxJ, nyJ, Jf
end

"""
    connect_mesh(rd, face_centroids, region_flags, cutcells; tol = 1e2 * eps())
    
Connects faces of a cut mesh to each other, returns `FToF` such that face 
`f` is connected to `FToF[f]`. 

Inputs:
- rd::RefElemData
- face_centroids = (face_centroids_x, face_centroids_y), where `face_centroids_x/y` 
                    are vectors of coordinates of face centroids
- `region_flags`, `cutcells` are return arguments from `PathIntersections.define_regions`
The keyword argument `tol` is the tolerance for matches between face centroids. 
"""    
function connect_mesh(rd, face_centroids, cutcell_data; tol = 1e2 * eps())

    @unpack region_flags, cut_faces_per_cell, cut_face_offsets = cutcell_data

    cells_per_dimension_x, cells_per_dimension_y = size(region_flags)
    num_cartesian_cells = sum(region_flags .== 0)
    num_cut_faces = sum(cut_faces_per_cell)
    num_total_faces = num_cut_faces + num_faces(rd.element_type) * num_cartesian_cells

    # element_indices[ex, ey] returns the global (flattened) element index into 
    # the arrays `xf.cartesian[:, e]` or `xf.cut[:, e]`
    element_indices = compute_element_indices(region_flags) 

    # compute face centroids for making face matches
    face_centroids_x, face_centroids_y = face_centroids

    
    # To determine face-to-face matches, we work with each background Cartesian element 
    # and search through the 4 neighboring background Cartesian elements for a match in 
    # the face centroids of the current cell and the face centroids of its neighbors.     
    # NOTE: this works because the cut cells can only have Cartesian neighbors across
    # flat-sided faces. It wouldn't work for meshes with curved interior interfaces.    

    FToF = collect(1:num_total_faces)
    for ex in 1:cells_per_dimension_x, ey in 1:cells_per_dimension_y

        e = element_indices[ex, ey]

        # Determine face indices of current cell. The face indices are determined 
        # from the flattened (e.g., not ex, ey) element ordering. 
        # NOTE: we search for matches between all faces of `e` and all faces of 
        # `e_nbr` because the ordering of faces is different for cut elements
        # and Cartesian elements. 
        if is_Cartesian(region_flags[ex, ey])
            face_ids = (1:num_faces(rd.element_type)) .+ (e-1) * num_faces(rd.element_type)
        elseif is_cut(region_flags[ex, ey])
            face_ids = (1:cut_faces_per_cell[e]) .+ cut_face_offsets[e]

            # we offset by the number of Cartesian faces so we can index globally
            # into the arrays `face_centroids_x`, `face_centroids_y`.
            face_ids = face_ids .+ length(face_centroids_x.cartesian) 
        end

        if is_inside_domain(ex, ey, region_flags)

            for f in 1:4 # each Cartesian background element has 4 neighbors

                ex_nbr, ey_nbr = neighbor_across_face(f, ex, ey)
                if is_inside_domain(ex_nbr, ey_nbr, region_flags)
                    e_nbr = element_indices[ex_nbr, ey_nbr]

                    # determine face indices of neighboring cells
                    if is_Cartesian(region_flags[ex_nbr, ey_nbr])                
                        nbr_face_ids = (1:num_faces(rd.element_type)) .+ (e_nbr-1) * num_faces(rd.element_type)
                    elseif is_cut(region_flags[ex_nbr, ey_nbr])
                        nbr_face_ids = (1:cut_faces_per_cell[e_nbr]) .+ cut_face_offsets[e_nbr]

                        # we offset by the number of Cartesian faces so we can index globally
                        # into the arrays `face_centroids_x`, `face_centroids_y`.
                        nbr_face_ids = nbr_face_ids .+ length(face_centroids_x.cartesian)
                    end

                    # check for matches in face and neighbor face centroids.
                    # note: we index into the global `face_centroids_x/y` container 
                    # rather than the `.cut` or `.cartesian subarrays`.
                    for i in face_ids
                        xy = SVector(face_centroids_x[i], face_centroids_y[i])
                        for j in nbr_face_ids
                            xy_nbr = SVector(face_centroids_x[j], face_centroids_y[j])
                            if norm(xy - xy_nbr) < tol * max(1, norm(xy), norm(xy_nbr))
                                FToF[i] = j  
                                # println("match found for f = $f, e=($ex, $ey), 
                                #          enbr=($ex_nbr, $ey_nbr)")
                            end
                        end
                    end

                end # if enbr is_inside_domain
            end
        end # if e is_inside_domain
    end

    return FToF
end

is_Cartesian(flag) = flag==0 ? true : false
is_cut(flag) = flag > 0

# returns the 1D quadrature used to build a RefElemData surface quadrature 
function get_1d_quadrature(rd::RefElemData{2, Quad})
    nfaces = num_faces(rd.element_type)
    num_points_per_face = length(rd.wf) ÷ nfaces
    rf = reshape(rd.rf, num_points_per_face, nfaces)
    wf = reshape(rd.wf, num_points_per_face, nfaces)
    
    # face ordering on a quad is -/+ x, -/+ y. face 3 = -y
    return rf[:, 3], wf[:, 3]
end

"""
    function MeshData(rd, geometry, vxyz...)

Creates a cut-cell mesh where the boundary is given by `curve`. Here, `coordinates_min`, 
`coordinates_max` contain `(smallest value of x, smallest value of y)` and 
`(largest value of x, largest value of y)`, and `cells_per_dimension_x/y` is the number 
of grid cells placed along each dimension.

Additional keywords:
- `ds`, `arc_tol`, `corner_tol`: see PathIntersections.jl docs
"""
function MeshData(rd::RefElemData, curves, cells_per_dimension_x, cells_per_dimension_y; 
                  quad_rule_face = get_1d_quadrature(rd), 
                  coordinates_min=(-1.0, -1.0), coordinates_max=(1.0, 1.0), 
                  ds = 1e-3, arc_tol = 1e-10, corner_tol = 1e-10)

    # compute intersections of curve with a background Cartesian grid.
    vx = LinRange(coordinates_min[1], coordinates_max[1], cells_per_dimension_x + 1)
    vy = LinRange(coordinates_min[2], coordinates_max[2], cells_per_dimension_y + 1)    

    # `regions` is a matrix of dimensions `(cells_per_dimension_x, cells_per_dimension_y)` with 3 values:
    #   *  1: cut cell
    #   *  0: Cartesian cell
    #   * -1: excluded cells (in the cut-out region)
    # 1) Get mesh intersections and curve stop points
    stop_pts = find_mesh_intersections((vx, vy), curves, ds, arc_tol, corner_tol,
                                        closed_list=true, closure_tol=1e-12)

    # 2) Calculate cutcells
    region_flags, cutcell_indices, cutcells = 
        define_regions((vx, vy), curves, stop_pts, binary_regions=false)

    # sort the vector of cut cells so that they match the ordering when 
    # iterating through Cartesian mesh indices via (ex, ey).
    cutcell_ordering = zeros(Int, length(cutcells))
    sk = 1
    for ex in 1:cells_per_dimension_x, ey in 1:cells_per_dimension_y 
        if is_cut(region_flags[ex, ey])
            cutcell_ordering[sk] = cutcell_indices[ex, ey] 
            sk += 1
        end        
    end
    permute!(cutcells, cutcell_ordering)

    # pack useful cut cell information together. 
    cut_faces_per_cell = count_cut_faces(cutcells)
    cut_face_offsets = [0; cumsum(cut_faces_per_cell)[1:end-1]] 
    cutcell_data = (; curves, region_flags, stop_pts, cutcells, cut_faces_per_cell, cut_face_offsets)

    # 3) Compute volume and face points
    x, y, rstxyzJ, J, xf, yf, nxJ, nyJ, Jf = 
        compute_geometric_data(rd, quad_rule_face, vx, vy, cutcell_data)

    # 4) Compute face-to-face connectivity by matching face centroids
    face_centroids = compute_face_centroids(rd, xf, yf, cutcell_data)
    FToF = connect_mesh(rd, face_centroids, cutcell_data)

    # 5) Compute node-to-node mappings
    num_total_faces = length(FToF)
    num_points_per_face = length(rd.rf) ÷ num_faces(rd.element_type)

    # WARNING: this only works if the same quadrature rule is used for all faces! 
    mapM = collect(reshape(1:num_points_per_face * num_total_faces, num_points_per_face, num_total_faces))
    mapP = copy(mapM)
    p = zeros(Int, num_points_per_face) # temp storage for a permutation vector
    for f in eachindex(FToF)
        idM = view(mapM, :, f)
        idP = view(mapM, :, FToF[f])
        xyzM = (view(xf, idM), view(yf, idM))
        xyzP = (view(xf, idP), view(yf, idP))
        StartUpDG.match_coordinate_vectors!(p, xyzM, xyzP)
        mapP[p, f] .= idP
    end
    mapB = findall(vec(mapM) .==vec(mapP)) # determine boundary nodes

    VXYZ = ntuple(_ -> nothing, 2)
    EToV = nothing

    Nq_cut = Np_cut(3 * rd.N)
    num_cartesian_cells = sum(region_flags .== 0)
    num_cut_cells = sum(region_flags .== 1)
    xq, yq, wJq = ntuple(_ -> ComponentArray(cartesian=zeros(rd.Nq, num_cartesian_cells), 
                                             cut=zeros(Nq_cut, num_cut_cells)), 3)

    is_periodic = (false, false)
    
    return MeshData(CutCellMesh(), VXYZ, EToV, FToF, (x, y), (xf, yf), (xq, yq), wJq, mapM, mapP, mapB, 
                    rstxyzJ, J, (nxJ, nyJ), Jf, is_periodic)

end

