using Celeste
using Base.Test
using SampleData
using CelesteTypes

import Images
import SDSS
import Util
import WCS

println("Running misc tests.")

function test_tile_image()
  blob, mp, three_bodies = gen_three_body_dataset();
  img = blob[3];

  # First with constant background
  tile_width = 20;
  tile = ImageTile(1, 1, img, tile_width);

  tiles = Images.break_image_into_tiles(img, tile_width);
  @test size(tiles) ==
    (int(ceil(img.H  / tile_width)), int(ceil(img.W / tile_width)))
  for tile in tiles
    @test tile.b == img.b
    @test tile.pixels == img.pixels[tile.h_range, tile.w_range]
    @test tile.epsilon == img.epsilon
    @test tile.iota == img.iota
    @test tile.constant_background == img.constant_background
  end

  # Then with varying background
  img.constant_background = false
  img.epsilon_mat = rand(size(img.pixels));
  img.iota_vec = rand(size(img.pixels)[1]);
  tiles = Images.break_image_into_tiles(img, tile_width);
  @test size(tiles) ==
    (int(ceil(img.H  / tile_width)), int(ceil(img.W / tile_width)))
  for tile in tiles
    @test tile.b == img.b
    @test tile.pixels == img.pixels[tile.h_range, tile.w_range]
    @test tile.epsilon_mat == img.epsilon_mat[tile.h_range, tile.w_range]
    @test tile.iota_vec == img.iota_vec[tile.h_range]
    @test tile.constant_background == img.constant_background
  end

  tile = tiles[2, 2]
  for h in 1:tile.h_width, w in 1:tile.w_width
    @test tile.pixels[h, w] == img.pixels[tile.h_range[h], tile.w_range[w]]
  end
end

function test_local_sources()
    # Coarse test that local_sources gets the right objects.

    srand(1)
    blob0 = Images.load_stamp_blob(dat_dir, "164.4311-39.0359");
    for b in 1:5
        blob0[b].H, blob0[b].W = 112, 238
        blob0[b].wcs = WCS.wcs_id
    end

    three_bodies = [
        sample_ce([4.5, 3.6], false),
        sample_ce([60.1, 82.2], true),
        sample_ce([71.3, 100.4], false),
    ]

    blob = Synthetic.gen_blob(blob0, three_bodies);

    mp = ModelInit.cat_init(three_bodies, patch_radius=20., tile_width=1000);
    @test mp.S == 3

    mp.tile_width = 1000
    tile = ImageTile(1, 1, blob[3], mp.tile_width);
    subset1000 = Images.local_sources(tile, mp, blob[3].wcs);
    @test subset1000 == [1,2,3]

    mp.tile_width = 10
    tile = ImageTile(1, 1, blob[3], mp.tile_width);
    subset10 = Images.local_sources(tile, mp, blob[3].wcs)
    @test subset10 == [1]

    last_tile = ImageTile(11, 24, blob[3], mp.tile_width)
    last_subset = Images.local_sources(last_tile, mp, blob[3].wcs)
    @test length(last_subset) == 0

    pop_tile = ImageTile(7, 9, blob[3], mp.tile_width)
    pop_subset = Images.local_sources(pop_tile, mp, blob[3].wcs)
    @test pop_subset == [2,3]
end


function test_local_sources_2()
    # Check that a larger blob gets the same number of objects
    # as a smaller blob.  (This is useful to check edge cases of
    # the polygon logic.)

    srand(1)
    blob0 = Images.load_stamp_blob(dat_dir, "164.4311-39.0359");
    one_body = [sample_ce([50., 50.], true),]

    for b in 1:5 blob0[b].H, blob0[b].W = 100, 100 end
    small_blob = Synthetic.gen_blob(blob0, one_body);

    for b in 1:5 blob0[b].H, blob0[b].W = 400, 400 end
    big_blob = Synthetic.gen_blob(blob0, one_body);

    mp = ModelInit.cat_init(one_body, patch_radius=35., tile_width=2);

    qx = 0
    for ww=1:50,hh=1:50
        tile = ImageTile(hh, ww, small_blob[2], mp.tile_width)
        if length(Images.local_sources(tile, mp, small_blob[2].wcs)) > 0
            qx += 1
        end
    end

    qy = 0
    for ww=1:200,hh=1:200
        tile = ImageTile(hh, ww, big_blob[1], mp.tile_width)
        if length(Images.local_sources(tile, mp, big_blob[1].wcs)) > 0
            qy += 1
        end
    end

    @test qy == qx
end


function test_local_sources_3()
    # Test local_sources using world coordinates.

    srand(1)
    test_b = 3 # Will test using this band only
    pix_loc = Float64[50., 50.]
    blob0 = Images.load_stamp_blob(dat_dir, "164.4311-39.0359");
    body_loc = WCS.pixel_to_world(blob0[test_b].wcs, pix_loc)
    one_body = [sample_ce(body_loc, true),]

    # Get synthetic blobs but with the original world coordinates.
    for b in 1:5 blob0[b].H, blob0[b].W = 100, 100 end
    blob = Synthetic.gen_blob(blob0, one_body);
    for b in 1:5 blob[b].wcs = blob0[b].wcs end

    tile_width = 1
    patch_radius_pix = 5.

    # Get a patch radius in world coordinates by looking at the world diagonals of
    # a pixel square of a certain size.
    world_quad = WCS.pixel_to_world(blob[test_b].wcs,
        [0. 0.; 0. patch_radius_pix; patch_radius_pix 0; patch_radius_pix patch_radius_pix])
    diags = [ world_quad[i, :]' - world_quad[i + 2, :]' for i=1:2 ]
    patch_radius = maximum([sqrt(dot(d, d)) for d in diags])

    mp = ModelInit.cat_init(one_body, patch_radius=patch_radius, tile_width=tile_width)

    # Source should be present
    tile = ImageTile(int(round(pix_loc[1] / tile_width)),
                     int(round(pix_loc[2] / tile_width)),
                     blob[test_b],
                     mp.tile_width);
    @assert Images.local_sources(tile, mp, blob[test_b].wcs) == [1]

    # Source should not match when you're 1 tile and a half away along the diagonal plus
    # the pixel radius from the center of the tile.
    tile = ImageTile(int(ceil((pix_loc[1] + 1.5 * tile_width * sqrt(2) +
                              patch_radius_pix) / tile_width)),
                     int(round(pix_loc[2] / tile_width)),
                     blob[test_b],
                     mp.tile_width)
    @assert Images.local_sources(tile, mp, blob[test_b].wcs) == []

    tile = ImageTile(int(round((pix_loc[1]) / tile_width)),
                     int(ceil((pix_loc[2]  + 1.5 * tile_width * sqrt(2) +
                           patch_radius_pix) / tile_width)),
                     blob[test_b],
                     mp.tile_width)
    @assert Images.local_sources(tile, mp, blob[test_b].wcs) == []
end


function test_tiling()
    srand(1)
    blob0 = Images.load_stamp_blob(dat_dir, "164.4311-39.0359")
    for b in 1:5
        blob0[b].H, blob0[b].W = 112, 238
    end
    three_bodies = [
        sample_ce([4.5, 3.6], false),
        sample_ce([60.1, 82.2], true),
        sample_ce([71.3, 100.4], false),
    ]
   blob = Synthetic.gen_blob(blob0, three_bodies)

    mp = ModelInit.cat_init(three_bodies)
    elbo = ElboDeriv.elbo(blob, mp)

    mp2 = ModelInit.cat_init(three_bodies, tile_width=10)
    elbo_tiles = ElboDeriv.elbo(blob, mp2)
    @test_approx_eq_eps elbo_tiles.v elbo.v 1e-5

    mp3 = ModelInit.cat_init(three_bodies, patch_radius=30.)
    elbo_patches = ElboDeriv.elbo(blob, mp3)
    @test_approx_eq_eps elbo_patches.v elbo.v 1e-5

    for s in 1:mp.S
        for i in 1:length(1:length(CanonicalParams))
            @test_approx_eq_eps elbo_tiles.d[i, s] elbo.d[i, s] 1e-5
            @test_approx_eq_eps elbo_patches.d[i, s] elbo.d[i, s] 1e-5
        end
    end

    mp4 = ModelInit.cat_init(three_bodies, patch_radius=35., tile_width=10)
    elbo_both = ElboDeriv.elbo(blob, mp4)
    @test_approx_eq_eps elbo_both.v elbo.v 1e-1

    for s in 1:mp.S
        for i in 1:length(1:length(CanonicalParams))
            @test_approx_eq_eps elbo_both.d[i, s] elbo.d[i, s] 1e-1
        end
    end
end


function test_sky_noise_estimates()
    blobs = Array(Blob, 2)
    blobs[1], mp, three_bodies = gen_three_body_dataset()  # synthetic
    blobs[2] = Images.load_stamp_blob(dat_dir, "164.4311-39.0359")  # real

    for blob in blobs
        for b in 1:5
            sdss_sky_estimate = blob[b].epsilon * blob[b].iota
            crude_estimate = median(blob[b].pixels)
            @test_approx_eq_eps sdss_sky_estimate / crude_estimate 1. .3
        end
    end
end


function test_util_bvn_cov()
    e_axis = .7
    e_angle = pi/5
    e_scale = 2.

    manual_11 = e_scale^2 * (1 + (e_axis^2 - 1) * (sin(e_angle))^2)
    util_11 = Util.get_bvn_cov(e_axis, e_angle, e_scale)[1,1]
    @test_approx_eq util_11 manual_11

    manual_12 = e_scale^2 * (1 - e_axis^2) * (cos(e_angle)sin(e_angle))
    util_12 = Util.get_bvn_cov(e_axis, e_angle, e_scale)[1,2]
    @test_approx_eq util_12 manual_12

    manual_22 = e_scale^2 * (1 + (e_axis^2 - 1) * (cos(e_angle))^2)
    util_22 = Util.get_bvn_cov(e_axis, e_angle, e_scale)[2,2]
    @test_approx_eq util_22 manual_22
end


function test_add_sensitive_floats()
  S = 3
  function generate_random_sf()
      sf1 = zero_sensitive_float(CanonicalParams, Float64, S)
      sf1.v = rand()
      sf1.d = rand(size(sf1.d))
      sf1.h = rand(size(sf1.h))
      sf1
  end

  sf1 = generate_random_sf();
  sf2 = generate_random_sf();

  sf3 = sf1 + sf2
  @test sf3.v == sf1.v + sf2.v
  @test sf3.d == sf1.d + sf2.d
  @test sf3.h == sf1.h + sf2.h


  sf_bad_size = zero_sensitive_float(CanonicalParams, Float64, S + 1);
  sf_bad_type = zero_sensitive_float(UnconstrainedParams, Float64, S);

  @test_throws ErrorException sf_bad_size + sf1
  @test_throws ErrorException sf_bad_type + sf1

  function sf_equal(sf1::SensitiveFloat, sf2::SensitiveFloat)
    sf1.v == sf2.v && sf2.d == sf2.d && sf1.h == sf2.h
  end

  # Check that recursive summing works.
  sf_vector = [ generate_random_sf() for i=1:3 ]
  @test sf_equal(sum(sf_vector), reduce(+, sf_vector))
  @test sf_equal(sum(sf_vector), sf_vector[1] + sf_vector[2] + sf_vector[3])

end

####################################################

test_tile_image()
test_util_bvn_cov()
test_sky_noise_estimates()
test_local_sources()
test_local_sources_2()
test_local_sources_3()
test_add_sensitive_floats()