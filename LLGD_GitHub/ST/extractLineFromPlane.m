function [p, l, a] = extractLineFromPlane(normal_vec_scaled, cluster_events, time_scale_factor)
    % 从 x-y-t 平面提取当前时刻的二维线段参数。
    % normal_vec_scaled 为缩放时空坐标中的平面法向量；
    % cluster_events 的列依次为 [x, y, t, polarity]。
    
    p = []; l = []; a = [];
    
    % 还原时间维度缩放前的法向量。
    n_scaled = normal_vec_scaled(:);
    n_orig = n_scaled;
    n_orig(3) = n_scaled(3) * time_scale_factor;
    
    n1 = n_orig(1); n2 = n_orig(2); n3 = n_orig(3);
    
    denom_dir = sqrt(n1^2 + n2^2);
    if denom_dir < 1e-8
        return;
    end
    l = [n2; -n1] / denom_dir;
    
    t_present = max(cluster_events(:, 3));
    centroid = mean(cluster_events(:, 1:3), 1);
    x_c = centroid(1); y_c = centroid(2); t_c = centroid(3);
    
    denom_p = n1^2 + n2^2;
    if denom_p < 1e-8
        return;
    end
    
    alpha = n3 * (t_present - t_c) / denom_p;
    p = [x_c; y_c] - alpha * [n1; n2];
    
    % 以支撑事件在直线方向上的投影范围估计长度。
    xy_points = cluster_events(:, 1:2);
    directions_from_p = xy_points - p';
    projections = directions_from_p * l;
    p = p + 0.5 * (min(projections) + max(projections)) * l;
    a = max(projections) - min(projections);
    
    if a < 0 || isnan(a)
        a = 0;
    end
end
