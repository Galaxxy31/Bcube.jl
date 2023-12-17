@testset "Algebra" begin
    @testset "Gradient" begin
        # We test the mapping of a gradient. The idea is to compute the integral of a function `f` whose
        # gradient is constant. Then the result must be this constant multiplied by the cell area.
        # But since we need to input a `ReferenceFunction`, we need to build `f ∘ F` where `F` is the mapping.
        # We also need a geometric function to compute the area of a convex quad.
        function convex_quad_area(cnodes)
            n1, n2, n3, n4 = cnodes
            return (
                abs((n1.x[1] - n3.x[1]) * (n2.x[2] - n4.x[2])) +
                abs((n2.x[1] - n4.x[1]) * (n1.x[2] - n3.x[2]))
            ) / 2
        end

        cnodes = [Node([0.0, 0.0]), Node([1.0, 0.0]), Node([2.0, 1.5]), Node([1.0, 1.5])]
        celltypes = [Quad4_t()]
        cell2node = Connectivity([4], [1, 2, 3, 4])
        mesh = Mesh(cnodes, celltypes, cell2node)
        # mesh = one_cell_mesh(:quad)

        c2n = connectivities_indices(mesh, :c2n)
        icell = 1
        cnodes = get_nodes(mesh, c2n[icell])
        ctype = cells(mesh)[icell]
        cInfo = CellInfo(mesh, icell)

        qDegree = Val(2)

        # Scalar test : gradient of scalar `f` in physical coordinates is [1, 2]
        function f1(ξ)
            x, y = mapping(cnodes, ctype, ξ)
            return x + 2y
        end
        g = ReferenceFunction(f1)

        _g = Bcube.materialize(∇(g), cInfo)
        res = Bcube.integrate_on_ref(_g, cInfo, Quadrature(qDegree))
        @test all(isapprox.(res ./ convex_quad_area(cnodes), [1.0, 2.0]))

        # Vector test : gradient of vector `f` in physical coordinates is [[1,2],[3,4]]
        function f2(ξ)
            x, y = mapping(cnodes, ctype, ξ)
            return [x + 2y, 3x + 4y]
        end
        g = ReferenceFunction(f2)

        _g = Bcube.materialize(∇(g), cInfo)
        res = Bcube.integrate_on_ref(_g, cInfo, Quadrature(qDegree))
        @test all(isapprox.(res ./ convex_quad_area(cnodes), [1.0 2.0; 3.0 4.0]))

        # Gradient of scalar PhysicalFunction
        # Physical function is [x,y] -> x so its gradient is [x,y] -> [1, 0]
        # so the integral is simply the volume of Ω
        mesh = one_cell_mesh(:quad)
        translate!(mesh, SA[-0.5, 1.0]) # the translation vector can be anything
        scale!(mesh, 2.0)
        dΩ = Measure(CellDomain(mesh), 1)
        @test Bcube.compute(∫(∇(PhysicalFunction(x -> x[1])) ⋅ [1, 1])dΩ)[1] == 16.0

        # Gradient of a vector PhysicalFunction
        mesh = one_cell_mesh(:quad)
        translate!(mesh, SA[π, -3.14]) # the translation vector can be anything
        scale!(mesh, 2.0)
        sizeU = spacedim(mesh)
        U = TrialFESpace(FunctionSpace(:Lagrange, 1), mesh; sizeU)
        V = TestFESpace(U)
        _f = x -> SA[2 * x[1]^2, x[1] * x[2]]
        f = PhysicalFunction(_f, sizeU)
        ∇f = PhysicalFunction(x -> ForwardDiff.jacobian(_f, x), (sizeU, spacedim(mesh)))
        dΩ = Measure(CellDomain(mesh), 3)
        l(v) = ∫(tr(∇(f) - ∇f) ⋅ v)dΩ
        _a = assemble_linear(l, V)
        @test all(isapprox.(_a, [0.0, 0.0, 0.0, 0.0]; atol = 100 * eps()))

        @testset "AbstractLazy" begin
            mesh = one_cell_mesh(:quad)
            scale!(mesh, 3.0)
            translate!(mesh, [4.0, 0.0])
            U_sca = TrialFESpace(FunctionSpace(:Lagrange, 1), mesh)
            U_vec = TrialFESpace(FunctionSpace(:Lagrange, 1), mesh; size = 2)
            V_sca = TestFESpace(U_sca)
            V_vec = TestFESpace(U_vec)
            u_sca = FEFunction(U_sca)
            u_vec = FEFunction(U_vec)
            dΩ = Measure(CellDomain(mesh), 2)
            projection_l2!(u_sca, PhysicalFunction(x -> 3 * x[1] - 4x[2]), dΩ)
            projection_l2!(
                u_vec,
                PhysicalFunction(x -> SA[2x[1] + 5x[2], 4x[1] - 3x[2]]),
                dΩ,
            )

            l1(v) = ∫((∇(π * u_sca) ⋅ ∇(2 * u_sca)) ⋅ v)dΩ
            l2(v) = ∫((∇(u_sca) ⋅ ∇(u_sca)) ⋅ v)dΩ

            a1_sca = assemble_linear(l1, V_sca)
            a2_sca = assemble_linear(l2, V_sca)
            @test all(a1_sca .≈ (2π .* a2_sca))

            V_vec = TestFESpace(U_vec)
            l1_vec(v) = ∫((∇(π * u_vec) * u_vec) ⋅ v)dΩ
            l2_vec(v) = ∫((∇(u_vec) * u_vec) ⋅ v)dΩ
            a1_vec = assemble_linear(l1_vec, V_vec)
            a2_vec = assemble_linear(l2_vec, V_vec)
            @test all(a1_vec .≈ (π .* a2_vec))
        end
    end

    @testset "algebra" begin
        f = PhysicalFunction(x -> 0)
        a = Bcube.NullOperator()
        @test dcontract(a, a) == a
        @test dcontract(rand(), a) == a
        @test dcontract(a, rand()) == a
        @test dcontract(f, a) == a
        @test dcontract(a, f) == a
    end

    @testset "UniformScaling" begin
        mesh = one_cell_mesh(:quad)
        U = TrialFESpace(FunctionSpace(:Lagrange, 1), mesh; size = 2)
        V = TestFESpace(U)
        p = PhysicalFunction(x -> 3)
        dΩ = Measure(CellDomain(mesh), 1)
        l(v) = ∫((p * I) ⊡ ∇(v))dΩ
        a = assemble_linear(l, V)
        @test all(a .≈ [-3.0, 3.0, -3.0, 3.0, -3.0, -3.0, 3.0, 3.0])
    end
end
