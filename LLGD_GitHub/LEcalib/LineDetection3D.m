classdef LineDetection3D
    properties
        pointData
        pointNum
        k
        scale
        magnitd
        pcaInfos
    end
    
    methods
        function obj = LineDetection3D()
        end

        function regions = pointCloudSegmentation(obj)
            pcaer = PCAFunctions();
            [obj.pcaInfos, obj.scale, obj.magnitd] = pcaer.Ori_PCA(obj.pointData, obj.k);

            thAngle = 15.0 / 180.0 * pi;
            regions = obj.regionGrow(thAngle);
        end

        function regions = regionGrow(obj, thAngle)
            thNormal = cos(thAngle);

            % Curvature-ordered region growing
            fun_lambda0 = arrayfun(@(x) x.lambda0, obj.pcaInfos);
            [~, fun_Sorted] = sort(fun_lambda0);
            
            percent = 0.9;
            idx = round(obj.pointNum * percent);
            isUsed = zeros(obj.pointNum, 1);
            regions = {};
            Num_isUsed = 0;
            
            for i = 1:idx
                idxStarter = fun_Sorted(i);
                if isUsed(idxStarter)
                    continue;
                end
                normalStarter = obj.pcaInfos(idxStarter).normal;
                ptStarter = obj.pointData(:, idxStarter);
                thRadius2 = (50 * obj.pcaInfos(idxStarter).scale)^2;
                
                clusterTemp = idxStarter;
                cluster_count = 1;
                
                while cluster_count <= length(clusterTemp)
                    idxSeed = clusterTemp(cluster_count);
                    normalSeed = obj.pcaInfos(idxSeed).normal;
                    thOrtho = obj.pcaInfos(idxSeed).scale;
                    th1_num = 0;
                    th2_num = 0;
                    th3_num = 0;
                    th0_num = 0;
                    th_pass = 0;
                    
                    num = length(obj.pcaInfos(idxSeed).idxAll);
                    
                    for j = 1:num
                        idxCur = obj.pcaInfos(idxSeed).idxAll(j);
                        if isUsed(idxCur)
                            th0_num = th0_num +1;
                            continue;
                        end
                        
                        % Normal agreement
                        normalCur = obj.pcaInfos(idxCur).normal;
                        t_Dev = abs(dot(normalCur, normalStarter));
                        
                        if t_Dev < thNormal
                            th1_num = th1_num + 1;
                            continue;
                        end
                        
                        % Orthogonal distance
                        ptCur = obj.pointData(:, idxCur);
                        t_rtho = abs(  (ptCur(1) - ptStarter(1)) * normalCur(1) ...
                                     + (ptCur(2) - ptStarter(2)) * normalCur(2) ...
                                     + (ptCur(3) - ptStarter(3)) * normalCur(3));
                        
                        if t_rtho > thOrtho 
                            th2_num = th2_num + 1;
                            continue;
                        end
                        
                        % Euclidean neighborhood extent
                        t_Radius = (ptCur(1) - ptStarter(1))^2 + (ptCur(2) - ptStarter(2))^2 + (ptCur(3) - ptStarter(3))^2;
                        if t_Radius > thRadius2
                            th3_num = th3_num + 1;
                            continue;
                        end
                        th_pass = th_pass+1;
                        clusterTemp = [clusterTemp; idxCur];
                        isUsed(idxCur) = 1;
                    end
                    
                    cluster_count = cluster_count + 1;
                end

                if length(clusterTemp) > 30
                    regions{end+1} = clusterTemp;
                    Num_isUsed = Num_isUsed + length(clusterTemp);
                else
                    isUsed(clusterTemp) = 0;
                end
            end
        end

        function regions = regionMerging(obj, thAngle, regions)
            thRegionSize = 600000;
            
            % Plane fitting for each region
            patches = repmat(struct('lambda0', 0, 'normal', [], 'idxIn', [], 'idxAll', [], 'scale', 0, 'planePt', []), length(regions), 1);
            
            for i = 1:length(regions)
                pointNumCur = length(regions{i});
                pointDataCur = zeros(pointNumCur, 3);
                
                for j = 1:pointNumCur
                    pt = obj.pointData(:, regions{i}(j));
                    pointDataCur(j, :) = [pt(1), pt(2), pt(3)];
                end
                
                pcaer = PCAFunctions();
                patches(i) = pcaer.PCASingle(pointDataCur);
                patches(i).idxAll = regions{i};
                
                scaleAvg = 0;
                for j = 1:length(patches(i).idxIn)
                    idx = regions{i}(patches(i).idxIn(j));
                    patches(i).idxIn(j) = idx;
                    scaleAvg = scaleAvg + obj.pcaInfos(idx).scale;
                end
                
                scaleAvg = scaleAvg / length(patches(i).idxIn);
                patches(i).scale = 5.0 * scaleAvg;
            end
            
            % Point-to-patch labels
            label = -ones(obj.pointNum, 1);
            for i = 1:length(regions)
                for j = 1:length(regions{i})
                    id = regions{i}(j);
                    label(id) = i;
                end
            end
            
            % Adjacent patches
            patchAdjacent = cell(length(patches), 1);
            
            for i = 1:length(patches)
                patchAdjacentTemp = {};
                pointAdjacentTemp = {};
                
                for j = 1:length(patches(i).idxIn)
                    id = patches(i).idxIn(j);
                    
                    for m = 1:length(obj.pcaInfos(id).idxIn)
                        idPoint = obj.pcaInfos(id).idxIn(m);
                        labelPatch = label(idPoint);
                        
                        if labelPatch == i || labelPatch < 0
                            continue;
                        end
                        
                        isNeighbor = any(obj.pcaInfos(idPoint).idxIn == id);
                        
                        if ~isNeighbor
                            continue;
                        end
                        
                        isIn = false;
                        n = 1;
                        while n <= length(patchAdjacentTemp)
                            if patchAdjacentTemp{n} == labelPatch
                                isIn = true;
                                break;
                            end
                            n = n + 1;
                        end
                        
                        if isIn
                            pointAdjacentTemp{n} = [pointAdjacentTemp{n}; idPoint];
                        else
                            patchAdjacentTemp = [patchAdjacentTemp, labelPatch];
                            pointAdjacentTemp{end+1} = idPoint;
                        end
                    end
                end
                
                for j = 1:length(pointAdjacentTemp)
                    pointAdjacentTemp{j} = unique(pointAdjacentTemp{j});
                    
                    if length(pointAdjacentTemp{j}) >= 3
                        patchAdjacent{i} = [patchAdjacent{i}, patchAdjacentTemp(j)];
                    end
                end
            end
            % Merge adjacent patches
            regions = {};
            mergedIndex = zeros(length(patches), 1);
            
            for i = 1:length(patches)
                if ~mergedIndex(i)
                    idxStarter = i;
                    normalStarter = patches(idxStarter).normal;
                    ptStarter = patches(idxStarter).planePt;
                    
                    patchIdx = idxStarter;
                    count = 1;
                    totalPoints = 0;
                    isEnough = false;
                    
                    while count <= length(patchIdx)
                        idxSeed = patchIdx(count);
                        normalSeed = patches(idxSeed).normal;
                        ptSeed = patches(idxSeed).planePt;
                        thOrtho = patches(idxSeed).scale;
                        
                        for j = 1:length(patchAdjacent{idxSeed})
                            idxCur = patchAdjacent{idxSeed}{j};
                            
                            if mergedIndex(idxCur)
                                continue;
                            end
                            
                            normalCur = patches(idxCur).normal;
                            ptCur = patches(idxCur).planePt;
                            
                            % Plane angle and offset
                            ptVector1 = ptCur - ptStarter;
                            ptVector2 = ptCur - ptSeed;
                            devAngle = acos(dot(normalStarter, normalCur));
                            devDis = abs(dot(normalStarter, ptVector1));
                            
                            if min(devAngle, pi - devAngle) < thAngle && devDis < thOrtho
                                patchIdx = [patchIdx; idxCur];
                                mergedIndex(idxCur) = 1;
                                
                                totalPoints = totalPoints + length(patches(idxCur).idxAll);
                                if totalPoints > thRegionSize
                                    isEnough = true;
                                    break;
                                end
                            end
                        end
                        
                        if isEnough
                            break;
                        end
                        count = count + 1;
                    end
                    
                    patchNewCur = [];
                    for j = 1:length(patchIdx)
                        idx = patchIdx(j);
                        patchNewCur = [patchNewCur; patches(idx).idxAll];
                    end
                    
                    if length(patchNewCur) > 100
                        regions{end+1} = patchNewCur;
                    end
                end %~mergedIndex(i)
            end
        end % function regions = regionMerging(obj, thAngle, regions)
        
    end
end
