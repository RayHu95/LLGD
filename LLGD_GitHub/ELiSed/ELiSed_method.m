function ELiSed_method(events, sensor_height, sensor_width)

    % ELiSeD 算法参数
    buffer_size       = 4000;          % 圆形缓冲区大小 (论文: 2500-8000)
    timestamp_cutoff  = 50;            % 时间戳过期阈值 (ms) (论文: 30-100ms)
    angle_tolerance   = deg2rad(22.5); % 方向角容差 (论文: ~23 deg)
    min_neighbors     = 3;             % 形成新支持区域所需的最小邻居数
    max_region_width  = 15;            % 支持区域最大宽度 (像素)，超限则分裂

    %% 3. 初始化 ELiSeD 数据结构
    % 最新时间戳图 (ON 和 OFF 事件分开，此处简化为只处理 ON)
    TL = zeros(sensor_height, sensor_width) - inf; 
    
    % 圆形事件缓冲区
    event_buffer = nan(buffer_size, 4); % [x, y, t, pol]
    buffer_idx = 1; % 下一个要写入的位置
    buffer_full = false;
    
    % 支持区域数据结构
    % 每个区域是一个结构体: {pixels: [N x 2], orientation: rad}
    support_regions = {};
    
    % 用于快速查找像素所属区域的映射图
    pixel_to_region = zeros(sensor_height, sensor_width);
    
    %% 4. 主处理循环：逐个处理事件
    for ev_idx = 1:size(events, 1)
        ev = events(ev_idx, :); % [x, y, t, polarity]
        x = round(ev(1)); y = round(ev(2)); t = ev(3);
        
        % --- 步骤 A: 更新圆形缓冲区 ---
        if buffer_full
            % 移除最旧的事件
            oldest_ev = event_buffer(buffer_idx, :);
            oldest_x = round(oldest_ev(1));
            oldest_y = round(oldest_ev(2));
            if oldest_x >= 1 && oldest_x <= sensor_width && ...
               oldest_y >= 1 && oldest_y <= sensor_height
                % 清除该像素的 TL 和 区域分配
                TL(oldest_y, oldest_x) = -inf;
                region_id = pixel_to_region(oldest_y, oldest_x);
                if region_id > 0
                    % 从对应支持区域中移除该像素
                    support_regions{region_id}.pixels(~ismember(support_regions{region_id}.pixels, [oldest_x, oldest_y], 'rows'), :);
                    pixel_to_region(oldest_y, oldest_x) = 0;
                end
            end
        else
            if buffer_idx > buffer_size
                buffer_full = true;
                buffer_idx = 1;
            end
        end
        
        % 添加新事件到缓冲区
        event_buffer(buffer_idx, :) = ev;
        buffer_idx = buffer_idx + 1;
        
        % --- 步骤 B: 更新 TL 图 ---
        if x >= 1 && x <= sensor_width && y >= 1 && y <= sensor_height
            TL(y, x) = t;
        end
        
        % --- 步骤 C: 计算当前事件位置的水平线方向 (ω) ---
        omega = NaN;
        if x >= 2 && x <= sensor_width-1 && y >= 2 && y <= sensor_height-1
            % 提取 3x3 TL 块
            tl_block = TL(y-1:y+1, x-1:x+1);
            % 应用时间戳截止
            tl_block(tl_block < (t - timestamp_cutoff)) = NaN;
            
            if sum(~isnan(tl_block(:))) > 5 % 至少需要一些有效点
                % 使用 Sobel 算子计算梯度
                Gx = [-1 0 1; -2 0 2; -1 0 1];
                Gy = [-1 -2 -1; 0 0 0; 1 2 1];
                dx = sum(sum(Gx .* tl_block, 'omitnan'));
                dy = sum(sum(Gy .* tl_block, 'omitnan'));
                omega = atan2(dy, dx); % 梯度方向
            end
        end
        
        if isnan(omega)
            continue; % 跳过无法计算方向的事件
        end
        
        % --- 步骤 D: 查找邻域内的候选像素/区域 ---
        candidates = [];
        candidate_regions = [];
        [ny, nx] = meshgrid(y-1:y+1, x-1:x+1);
        neighbor_coords = [nx(:), ny(:)];
        
        for n = 1:size(neighbor_coords, 1)
            nx_i = neighbor_coords(n, 1);
            ny_i = neighbor_coords(n, 2);
            if nx_i < 1 || nx_i > sensor_width || ny_i < 1 || ny_i > sensor_height
                continue;
            end
            
            % 检查该邻居是否有缓冲事件且方向匹配
            if TL(ny_i, nx_i) > (t - timestamp_cutoff) % 有效时间戳
                % 获取该像素的方向（如果已计算）
                % 这里简化：我们只检查它是否属于一个已有区域
                region_id_n = pixel_to_region(ny_i, nx_i);
                if region_id_n > 0
                    region_omega = support_regions{region_id_n}.orientation;
                    if abs(wrapToPi(omega - region_omega)) <= angle_tolerance
                        candidates = [candidates; nx_i, ny_i];
                        if ~ismember(region_id_n, candidate_regions)
                            candidate_regions = [candidate_regions, region_id_n];
                        end
                    end
                else
                    % 该像素是孤立的，但方向未知。我们暂时跳过。
                    % 更完整的实现会缓存每个像素的 omega。
                end
            end
        end
        
        % 将当前像素加入候选
        candidates = [candidates; x, y];
        
        % --- 步骤 E: 分配像素到支持区域 ---
        if ~isempty(candidate_regions)
            % 分配给最老的区域 (通过区域ID简单模拟)
            target_region_id = min(candidate_regions);
            % 将所有候选像素分配给该区域
            for c = 1:size(candidates, 1)
                cx = candidates(c, 1); cy = candidates(c, 2);
                if cx >= 1 && cx <= sensor_width && cy >= 1 && cy <= sensor_height
                    % 从旧区域移除（如果存在）
                    old_region_id = pixel_to_region(cy, cx);
                    if old_region_id > 0 && old_region_id ~= target_region_id
                        support_regions{old_region_id}.pixels(~ismember(support_regions{old_region_id}.pixels, [cx, cy], 'rows'), :);
                    end
                    % 添加到目标区域
                    support_regions{target_region_id}.pixels(end+1, :) = [cx, cy]; %#ok<AGROW>
                    pixel_to_region(cy, cx) = target_region_id;
                end
            end
            % 更新区域方向为平均方向
            all_omegas = omega; % 至少包含当前omega
            for c = 1:size(candidates, 1)
                cx = candidates(c, 1); cy = candidates(c, 2);
                if cx >= 1 && cx <= sensor_width && cy >= 1 && cy <= sensor_height
                    % 这里简化，实际应存储每个像素的omega
                end
            end
            support_regions{target_region_id}.orientation = omega; % 简化更新
        elseif size(candidates, 1) >= min_neighbors
            % 创建新的支持区域
            new_region_id = length(support_regions) + 1;
            support_regions{new_region_id} = struct(...
                'pixels', candidates, ...
                'orientation', omega);
            for c = 1:size(candidates, 1)
                cx = candidates(c, 1); cy = candidates(c, 2);
                if cx >= 1 && cx <= sensor_width && cy >= 1 && cy <= sensor_height
                    pixel_to_region(cy, cx) = new_region_id;
                end
            end
        end
    end
    
    %% 5. 后处理：过滤和拟合线段
    line_segments = {};
    min_region_size = 10; % 最小像素数
    
    for r = 1:length(support_regions)
        region = support_regions{r};
        pixels = region.pixels;
        
        if size(pixels, 1) < min_region_size
            continue; % 忽略太小的区域
        end
        
        % 使用图像矩计算主轴 (论文 Section III.B)
        % 中心矩
        mu_10 = mean(pixels(:,1));
        mu_01 = mean(pixels(:,2));
        
        % 二阶中心矩
        mu_20 = mean((pixels(:,1) - mu_10).^2);
        mu_02 = mean((pixels(:,2) - mu_01).^2);
        mu_11 = mean((pixels(:,1) - mu_10) .* (pixels(:,2) - mu_01));
        
        % 计算主轴方向
        theta = 0.5 * atan2(2*mu_11, mu_20 - mu_02);
        
        % 主轴向量
        major_axis = [cos(theta), sin(theta)];
        
        % 投影到主轴上以确定线段端点
        projections = pixels * major_axis';
        [~, idx_start] = min(projections);
        [~, idx_end] = max(projections);
        
        start_pt = pixels(idx_start, :);
        end_pt = pixels(idx_end, :);
        
        line_segments{end+1} = [start_pt; end_pt];
    end
    
    fprintf('Detected %d line segment(s).\n', length(line_segments));
    
    %% 6. 可视化结果
    figure('Position', [100, 100, 1200, 500]);

    % 子图 1: 原始事件渲染图 (20ms 时间片)
    subplot(1, 2, 1);
    time_window = 20; % ms
    latest_t = max(events(:,3));
    mask = events(:,3) > (latest_t - time_window);
    rendered_img = zeros(sensor_height, sensor_width);
    rendered_img(sub2ind(size(rendered_img), events(mask,2), events(mask,1))) = 1;
    imagesc(rendered_img);
    colormap(gray);
    axis image;
    title('Rendered Events (last 20ms)');
    xlabel('x'); ylabel('y');

    % 子图 2: 检测到的线段
    subplot(1, 2, 2);
    hold on;
    scatter(events(:,1), events(:,2), 1, 'k', 'MarkerFaceAlpha', 0.1);
    colors = lines(length(line_segments));
    for i = 1:length(line_segments)
        seg = line_segments{i};
        plot(seg([1,2], 1), seg([1,2], 2), '-', 'Color', colors(i,:), 'LineWidth', 2);
    end
    axis([1 sensor_width 1 sensor_height]);
    set(gca, 'YDir', 'reverse');
    title('Detected Line Segments (ELiSeD)');
    xlabel('x'); ylabel('y');
    legend_str = arrayfun(@(i) sprintf('Segment %d', i), 1:length(line_segments), 'UniformOutput', false);
    if ~isempty(legend_str)
        legend(legend_str, 'Location', 'best');
    end


end