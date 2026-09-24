function detected_lines = ST_method(events, sensor_height, sensor_width)

    cluster_threshold = 15;
    plane_threshold   = 0.5;
    max_cluster_age   = 0.5;
    time_scale_factor = 1000;

    [clusters, idx] = initialClustering(events, 5.0);
    num_clusters = length(clusters);
    
    detected_lines = {};
    for i = 1:num_clusters
        cluster_events = clusters{i};
        
        if size(cluster_events, 1) < cluster_threshold
            continue;
        end
        
        t_span = max(cluster_events(:,3)) - min(cluster_events(:,3));
        if t_span > max_cluster_age
            continue;
        end
        
        X = cluster_events(:, 1:3);
        X(:,3) = X(:,3) * time_scale_factor;
        [coeff, ~, latent] = pca(X);
        min_eigenvalue = latent(end);
        
        if min_eigenvalue < plane_threshold
            normal_vec = coeff(:, end)';
            [p, l, a] = extractLineFromPlane(normal_vec, cluster_events, time_scale_factor);
            if ~isempty(p)
                detected_lines{end+1} = struct('point', p, 'direction', l, 'length', a, 'events', cluster_events, 'idx' ,idx{i});
            end
        end
    end
end
