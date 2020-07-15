#include "bempp_base_types.h"
#include "bempp_helpers.h"
#include "bempp_spaces.h"
#include "kernels.h"

__kernel void evaluate_scalar_potential_novec(__global REALTYPE *grid,
                                              __global uint* indices,
                                              __global int* normalSigns,
                                              __global REALTYPE *evalPoints,
                                              __global REALTYPE *coefficients,
                                              __constant REALTYPE* quadPoints,
                                              __constant REALTYPE *quadWeights,
                                              __global REALTYPE *globalResult) {
  size_t gid[2];

  gid[0] = get_global_id(0);
  gid[1] = get_global_id(1);

  size_t elementIndex = indices[gid[1]];

  size_t lid = get_local_id(1);
  size_t groupId = get_group_id(1);
  size_t numGroups = get_num_groups(1);

  REALTYPE3 evalGlobalPoint;
  REALTYPE3 surfaceGlobalPoint;

  REALTYPE3 corners[3];
  REALTYPE3 jacobian[2];
  REALTYPE3 normal;
  REALTYPE3 dummy;

  REALTYPE2 point;

  REALTYPE intElement;
  REALTYPE value[NUMBER_OF_SHAPE_FUNCTIONS];

  size_t quadIndex;
  size_t index;

  evalGlobalPoint =
      (REALTYPE3)(evalPoints[3 * gid[0] + 0], evalPoints[3 * gid[0] + 1],
                  evalPoints[3 * gid[0] + 2]);

  __local REALTYPE localResult[WORKGROUP_SIZE][2];
  REALTYPE myResult[2] = {M_ZERO, M_ZERO};

  REALTYPE kernelValue[2];
  REALTYPE tempResult[2];
  REALTYPE myCoefficients[NUMBER_OF_SHAPE_FUNCTIONS][2];

#ifndef COMPLEX_COEFFICIENTS
  for (int index = 0; index < NUMBER_OF_SHAPE_FUNCTIONS; ++index){
    myCoefficients[index][0] =
        coefficients[NUMBER_OF_SHAPE_FUNCTIONS * elementIndex + index];
    myCoefficients[index][1] = M_ZERO;
  }
#else
  for (int index = 0; index < NUMBER_OF_SHAPE_FUNCTIONS; ++index) {
    myCoefficients[index][0] =
        coefficients[2 * (NUMBER_OF_SHAPE_FUNCTIONS * elementIndex + index)];
    myCoefficients[index][1] =
        coefficients[2 * (NUMBER_OF_SHAPE_FUNCTIONS * elementIndex + index) + 1];
  }
#endif

  getCorners(grid, elementIndex, corners);
  getJacobian(corners, jacobian);
  getNormalAndIntegrationElement(jacobian, &normal, &intElement);

  updateNormals(elementIndex, normalSigns, &normal);

  for (quadIndex = 0; quadIndex < NUMBER_OF_QUAD_POINTS; ++quadIndex) {
    point = (REALTYPE2)(quadPoints[2 * quadIndex], quadPoints[2 * quadIndex + 1]);
    BASIS(SHAPESET, evaluate)(&point, &value[0]);
    surfaceGlobalPoint = getGlobalPoint(corners, &point);
    KERNEL(novec)
    (evalGlobalPoint, surfaceGlobalPoint, dummy, normal, kernelValue);

    tempResult[0] = M_ZERO;
    tempResult[1] = M_ZERO;
    for (index = 0; index < NUMBER_OF_SHAPE_FUNCTIONS; ++index) {
      tempResult[0] += myCoefficients[index][0] * value[index];
      tempResult[1] += myCoefficients[index][1] * value[index];
    }
    tempResult[0] *= quadWeights[quadIndex];
    tempResult[1] *= quadWeights[quadIndex];

    myResult[0] +=
        tempResult[0] * kernelValue[0] - tempResult[1] * kernelValue[1];
    myResult[1] +=
        tempResult[0] * kernelValue[1] + tempResult[1] * kernelValue[0];
  }

  localResult[lid][0] = myResult[0] * intElement;
  localResult[lid][1] = myResult[1] * intElement;
  barrier(CLK_LOCAL_MEM_FENCE);

  if (lid == 0) {
    for (index = 1; index < WORKGROUP_SIZE; ++index) {
      localResult[0][0] += localResult[index][0];
      localResult[0][1] += localResult[index][1];
    }
    globalResult[2 * (gid[0] * numGroups + groupId)] += localResult[0][0];
    globalResult[2 * (gid[0] * numGroups + groupId) + 1] += localResult[0][1];
  }
}
