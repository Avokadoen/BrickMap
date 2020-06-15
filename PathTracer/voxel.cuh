#pragma once

#include "gtx/vec_swizzle.hpp"

	__device__ __forceinline unsigned int
	morton(unsigned int x) {
	x = (x ^ (x << 16)) & 0xff0000ff, x = (x ^ (x << 8)) & 0x0300f00f;
	x = (x ^ (x << 4)) & 0x030c30c3, x = (x ^ (x << 2)) & 0x09249249;
	return x;
}

// From http://www.jcgt.org/published/0006/02/01/
__device__ bool intersect_aabb_branchless2(const glm::vec3& origin, const glm::vec3& direction, float& tmin) {
	constexpr glm::vec3 box_min = { 0, 0, 0 };
	constexpr glm::vec3 box_max = { grid_size, grid_size, grid_height };

	const glm::vec3 t1 = (box_min - origin) / direction;
	const glm::vec3 t2 = (box_max - origin) / direction;
	const glm::vec3 tMin = glm::min(t1, t2);
	const glm::vec3 tMax = glm::max(t1, t2);

	tmin = glm::max(glm::max(tMin.x, 0.f), glm::max(tMin.y, tMin.z));
	return glm::min(tMax.x, glm::min(tMax.y, tMax.z)) > tmin;
}

__device__ inline bool intersect_byte(glm::vec3 origin, glm::vec3 direction, glm::vec3& normal, float& distance, uint8_t byte) {
	glm::ivec3 pos = origin;

	glm::vec3 cb;
	cb.x = direction.x > 0.f ? pos.x + 1 : pos.x;
	cb.y = direction.y > 0.f ? pos.y + 1 : pos.y;
	cb.z = direction.z > 0.f ? pos.z + 1 : pos.z;
	glm::ivec3 out;
	out.x = direction.x > 0.f ? 2 : -1;
	out.y = direction.y > 0.f ? 2 : -1;
	out.z = direction.z > 0.f ? 2 : -1;
	glm::vec3 step;
	step.x = direction.x > 0.f ? 1.f : -1.f;
	step.y = direction.y > 0.f ? 1.f : -1.f;
	step.z = direction.z > 0.f ? 1.f : -1.f;

	glm::vec3 rdinv = 1.f / direction;
	glm::vec3 tmax;
	tmax.x = direction.x != 0.f ? (cb.x - origin.x) * rdinv.x : 1000000.f;
	tmax.y = direction.y != 0.f ? (cb.y - origin.y) * rdinv.y : 1000000.f;
	tmax.z = direction.z != 0.f ? (cb.z - origin.z) * rdinv.z : 1000000.f;
	glm::vec3 tdelta = step * rdinv;

	pos = pos % 2;

	distance = 0.f;
	int step_axis = -1;
	glm::vec3 mask;
	// Stepping through grid
	while (1) {
		if (byte & (1 << (pos.x + pos.y * 2 + pos.z * 4))) {
			if (step_axis > -1) {
				normal = glm::vec3(0, 0, 0);
				normal[step_axis] = -step[step_axis];
				distance = tmax[step_axis] - tdelta[step_axis];
			}
			return true;
		}

		step_axis = (tmax.x < tmax.y) ? ((tmax.x < tmax.z) ? 0 : 2) : ((tmax.y < tmax.z) ? 1 : 2);
		mask.x = tmax.x < tmax.y && tmax.x < tmax.z;
		mask.y = tmax.y <= tmax.x && tmax.y < tmax.z;
		mask.z = tmax.z <= tmax.x && tmax.z <= tmax.y;

		pos += mask * step;
		if (pos[step_axis] == out[step_axis])
			break;
		tmax += mask * tdelta;
	}
	return false;
}

__device__ inline bool intersect_brick(glm::vec3 origin, glm::vec3 direction, glm::vec3& normal, float& distance, Brick* brick) {
	glm::ivec3 pos = origin;

	glm::vec3 cb;
	cb.x = direction.x > 0.f ? pos.x + 1 : pos.x;
	cb.y = direction.y > 0.f ? pos.y + 1 : pos.y;
	cb.z = direction.z > 0.f ? pos.z + 1 : pos.z;
	glm::ivec3 out;
	out.x = direction.x > 0.f ? brick_size : -1;
	out.y = direction.y > 0.f ? brick_size : -1;
	out.z = direction.z > 0.f ? brick_size : -1;
	glm::vec3 step;
	step.x = direction.x > 0.f ? 1.f : -1.f;
	step.y = direction.y > 0.f ? 1.f : -1.f;
	step.z = direction.z > 0.f ? 1.f : -1.f;
	
	glm::vec3 rdinv = 1.f / direction;
	glm::vec3 tmax;
	tmax.x = direction.x != 0.f ? (cb.x - origin.x) * rdinv.x : 1000000.f;
	tmax.y = direction.y != 0.f ? (cb.y - origin.y) * rdinv.y : 1000000.f;
	tmax.z = direction.z != 0.f ? (cb.z - origin.z) * rdinv.z : 1000000.f;
	glm::vec3 tdelta = step * rdinv;

	pos = pos % 8;

	distance = 0.f;
	int step_axis = -1;
	glm::vec3 mask;
	// Stepping through grid
	while (1) {
		int sub_data = (pos.x + pos.y * brick_size + pos.z * brick_size * brick_size) / 32;
		int bit = (pos.x + pos.y * brick_size + pos.z * brick_size * brick_size) % 32;

		if (brick->data[sub_data] & (1 << bit)) {
			if (step_axis > -1) {
				normal = glm::vec3(0, 0, 0);
				normal[step_axis] = -step[step_axis];
				distance = tmax[step_axis] - tdelta[step_axis];
			}
			return true;
		}

		step_axis = (tmax.x < tmax.y) ? ((tmax.x < tmax.z) ? 0 : 2) : ((tmax.y < tmax.z) ? 1 : 2);
		mask.x = tmax.x < tmax.y && tmax.x < tmax.z;
		mask.y = tmax.y <= tmax.x && tmax.y < tmax.z;
		mask.z = tmax.z <= tmax.x && tmax.z <= tmax.y;

		pos += mask * step;
		if (pos[step_axis] == out[step_axis])
			break;
		tmax += mask * tdelta;
	}
	return false;
}

__device__ inline bool intersect_voxel(glm::vec3 origin, glm::vec3 direction, glm::vec3& normal, float& distance, Scene::GPUScene scene, glm::ivec3 camera_position) {
	float tminn;
	if (!intersect_aabb_branchless2(origin, direction, tminn)) {
		return false;
	}

	// Move ray to hitpoint
	if (tminn > 0) {
		origin += direction * tminn;

		constexpr glm::vec3 scale = (glm::vec3(1.f / (grid_size / static_cast<float>(grid_height)), 1.f / (grid_size / static_cast<float>(grid_height)), 1.f / (grid_height / static_cast<float>(grid_height))));
		constexpr glm::vec3 grid_center = glm::vec3(grid_size / 2.f, grid_size / 2.f, grid_height / 2.f);

		glm::vec3 to_center = glm::abs(grid_center - origin) * scale;
		glm::vec3 signs = glm::sign(origin - grid_center);
		to_center /= glm::max(to_center.x, glm::max(to_center.y, to_center.z));
		normal = signs * glm::trunc(to_center + 0.000001f);

		origin -= normal * epsilon;
	}
	origin /= 8.f;
	glm::ivec3 pos = origin;

	// Needed because sometimes the AABB intersect returns true while the ray is actually outside slightly. Only happens for faces that touch the AABB sides
	if (pos.x < 0 || pos.x >= cells || pos.y < 0 || pos.y >= cells || pos.z < 0 || pos.z >= cells_height) {
		return false;
	}

	glm::vec3 cb;
	cb.x = direction.x > 0.f ? pos.x + 1 : pos.x;
	cb.y = direction.y > 0.f ? pos.y + 1 : pos.y;
	cb.z = direction.z > 0.f ? pos.z + 1 : pos.z;
	glm::ivec3 out;
	out.x = direction.x > 0.f ? cells : -1;
	out.y = direction.y > 0.f ? cells : -1;
	out.z = direction.z > 0.f ? cells_height : -1;
	glm::vec3 step;
	step.x = direction.x > 0.f ? 1.f : -1.f;
	step.y = direction.y > 0.f ? 1.f : -1.f;
	step.z = direction.z > 0.f ? 1.f : -1.f;
	
	glm::vec3 rdinv = 1.f / direction;
	glm::vec3 tmax;
	tmax.x = direction.x != 0.f ? (cb.x - origin.x) * rdinv.x : 1000000.f;
	tmax.y = direction.y != 0.f ? (cb.y - origin.y) * rdinv.y : 1000000.f;
	tmax.z = direction.z != 0.f ? (cb.z - origin.z) * rdinv.z : 1000000.f;
	glm::vec3 tdelta = step * rdinv;

	int step_axis = -1;
	glm::vec3 mask;

	while (1) {
		int supercell_index = pos.x / supergrid_cell_size + (pos.y / supergrid_cell_size) * supergrid_xy + (pos.z / supergrid_cell_size) * supergrid_xy * supergrid_xy;
		uint32_t& index = scene.indices[supercell_index][(pos.x % supergrid_cell_size) + (pos.y % supergrid_cell_size) * supergrid_cell_size + (pos.z % supergrid_cell_size) * supergrid_cell_size * supergrid_cell_size];

		if (index) {
			float new_distance = 0.f;
			if (step_axis != -1) {
				normal = glm::vec3(0, 0, 0);
				normal[step_axis] = -step[step_axis];
				new_distance = tmax[step_axis] - tdelta[step_axis];
			}

			glm::ivec3 difference = camera_position - pos;
			int lod_distance_squared = difference.x * difference.x + difference.y * difference.y + difference.z * difference.z;
			float sub_distance = 0.f;

			if (lod_distance_squared > lod_distance_8x8x8) {
				distance = new_distance * 8.f + tminn;
				return true;
			} else if (lod_distance_squared > lod_distance_2x2x2) {
				// For some reason the normal displacement has to be made even smaller
				if (intersect_byte((origin + direction * new_distance) * 2.f - normal * 0.2f * epsilon, direction, normal, sub_distance, (index & brick_lod_bits) >> 12)) {
					distance = new_distance * 8.f + sub_distance * 4.f + tminn;
					return true;
				}
			} else {
				if (index & brick_loaded_bit) {
					Brick* p = scene.bricks[supercell_index];
					if (intersect_brick((origin + direction * new_distance) * 8.f - normal * epsilon, direction, normal, sub_distance, &p[index & brick_index_bits])) {
						distance = new_distance * 8.f + sub_distance + tminn;
						return true;
					}
				} else if (index & brick_unloaded_bit) {
					uint32_t old = atomicOr(&index, brick_requested_bit);

					if (!(old & brick_requested_bit)) {
						// request chunk to be loaded

						const unsigned int load_index = atomicAdd(scene.brick_load_queue_count, 1);
						if (load_index < brick_load_queue_size) {
							scene.brick_load_queue[load_index] = pos;
						} else {
							atomicAnd(&index, ~brick_requested_bit);
							// ToDo happens a lot. Fix?
						}
					}

					distance = new_distance * 8.f + tminn;
					return true;
				}
			}
		}

		step_axis = (tmax.x < tmax.y) ? ((tmax.x < tmax.z) ? 0 : 2) : ((tmax.y < tmax.z) ? 1 : 2);

		mask.x = tmax.x < tmax.y && tmax.x < tmax.z;
		mask.y = tmax.y <= tmax.x && tmax.y < tmax.z;
		mask.z = tmax.z <= tmax.x && tmax.z <= tmax.y;

		pos += mask * step;
		if (pos[step_axis] == out[step_axis])
			break;
		tmax += mask * tdelta;
	}
	return false;
}