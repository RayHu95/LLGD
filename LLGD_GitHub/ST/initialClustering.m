function [clusters, idx] = initialClustering(events, spatial_dist)
    % 简单的空间聚类：贪心最近邻
    clusters = {}; idx = {};
    assigned = false(size(events,1), 1);
    
    for i = 1:size(events,1)
        if assigned(i)
            continue;
        end
        
        x_i = events(i,1); y_i = events(i,2);
        cluster_idx = {i};
        
        % 查找附近未分配的事件
        for j = i+1:size(events,1)
            if ~assigned(j)
                dist = sqrt((events(j,1)-x_i)^2 + (events(j,2)-y_i)^2);
                if dist < spatial_dist
                    cluster_idx{end+1} = j;
                    assigned(j) = true;
                end
            end
        end
        
        clusters{end+1} = events([cluster_idx{:}], :);
        idx{end+1} = [cluster_idx{:}];
    end
end