classdef PCAFunctions
    methods
        function [pcaInfos, scale, magnitd] = Ori_PCA(obj, cloud, k)
            MINVALUE = 1e-7;
            pointNum = length(cloud);
            pcaInfos = repmat(struct('lambda0', 0, 'normal', [], 'idxAll', [], 'idxIn', [], 'scale', 0), pointNum, 1);
            
            pointData = cloud';
            kdtree = KDTreeSearcher(pointData);
            
            % Local nearest-neighbor search
            [out_indices, ~] = knnsearch(kdtree, pointData, 'K', k+1); % +1 to exclude self
            
            scale = 0.0;
            for i = 1:pointNum
                ki = k; % Number of neighbors
                neighbors = out_indices(i, 2:end); % Exclude self

                % Local covariance eigendecomposition
                h_mean = mean(pointData(neighbors, 1:3), 1);
                centered = pointData(neighbors, 1:3) - h_mean;
                h_cov = (centered' * centered) / ki;

                [V, D] = eig(h_cov);
                evals = diag(D);
                [~, idx] = sort(evals, 'descend');
                h_cov_evectors = V(:, idx);
                h_cov_evals = evals(idx);
                
                pcaInfos(i).idxAll = neighbors;
                
                % Distance to the fourth neighbor
                idx_n = neighbors(4);
                dx = cloud(1, idx_n) - cloud(1, i);
                dy = cloud(2, idx_n) - cloud(2, i);
                dz = cloud(3, idx_n) - cloud(3, i);
                scaleTemp = sqrt(dx^2 + dy^2 + dz^2);
                pcaInfos(i).scale = scaleTemp;
                scale = scale + scaleTemp;
                              
                t = h_cov_evals(1) + h_cov_evals(2) + h_cov_evals(3) + (randi(10) + 1) * MINVALUE;
                pcaInfos(i).lambda0 = h_cov_evals(3) / t;
                pcaInfos(i).normal = h_cov_evectors(:, 3);
                pcaInfos(i).idxIn = pcaInfos(i).idxAll;
            end
            
            scale = scale / pointNum;
            magnitd = sqrt(cloud(1, 1)^2 + cloud(2, 1)^2 + cloud(3, 1)^2);
        end
        
        function pcaInfo = PCASingle(obj, pointData)
            k = size(pointData, 1);
            a = 1.4826;
            thRz = 2.5;
            pcaInfo = struct('lambda0', 0, 'normal', [], 'idxIn', [], 'idxAll', [], 'scale', 0, 'planePt', []);
            
            pcaInfo.idxIn = (1:k)';
            h_mean = mean(pointData, 1)';
            
            centered = pointData' - h_mean;
            h_cov = (centered * centered') / k;

            [V, D] = eig(h_cov);
            evals = diag(D);
            [~, idx] = sort(evals, 'descend');
            h_cov_evectors = V(:, idx);
            h_cov_evals = evals(idx);
            
            pcaInfo.idxAll = pcaInfo.idxIn;
            pcaInfo.lambda0 = h_cov_evals(3) / sum(h_cov_evals);
            pcaInfo.normal = h_cov_evectors(:, 3);
            pcaInfo.planePt = h_mean;
            
            % MCMD outlier removal
            pcaInfo = obj.MCMD_OutlierRemoval(pointData, pcaInfo);
        end
        
        function pcaInfo = MCMD_OutlierRemoval(obj, pointData, pcaInfo)
            a = 1.4826;
            thRz = 2.5;
            num = length(pcaInfo.idxAll);
            
            % Orthogonal distances from the fitted plane
            h_mean = zeros(3, 1);
            for j = 1:length(pcaInfo.idxIn)
                idx = pcaInfo.idxIn(j);
                h_mean = h_mean + pointData(idx, :)';
            end
            h_mean = h_mean / length(pcaInfo.idxIn);
            
            ODs = zeros(num, 1);
            for j = 1:num
                idx = pcaInfo.idxAll(j);
                pt = pointData(idx, :)';
                OD = abs(dot((pt - h_mean), pcaInfo.normal));
                ODs(j) = OD;
            end
            
            median_OD = median(ODs);
            abs_diff_ODs = abs(ODs - median_OD);
            MAD_OD = a * median(abs_diff_ODs) + 1e-6;
            
            idxInlier = [];
            for j = 1:num
                Rzi = abs(ODs(j) - median_OD) / MAD_OD;
                if Rzi < thRz
                    idx = pcaInfo.idxAll(j);
                    idxInlier = [idxInlier; idx];
                end
            end
            
            pcaInfo.idxIn = idxInlier;
        end
        
        function m = meadian(~, dataset)
            dataset = sort(dataset);
            if mod(length(dataset), 2) == 0
                m = dataset(length(dataset)/2);
            else
                m = (dataset(length(dataset)/2) + dataset(length(dataset)/2 + 1)) / 2.0;
            end
        end
    end
end
