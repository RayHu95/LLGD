function line_segments = robustLineDetection(img, varargin)
    % 鲁棒的线段检测（不依赖lineSegmentDetector）
    
    p = inputParser;
    addParameter(p, 'Method', 'enhanced_hough', @ischar);
    addParameter(p, 'MinLength', 15, @isnumeric);
    addParameter(p, 'Sigma', 0.8, @isnumeric);
    parse(p, varargin{:});
    
    % 图像预处理
    if size(img, 3) == 3
        gray_img = rgb2gray(img);
    else
        gray_img = img;
    end
    
    % 可选：去噪
    gray_img = imgaussfilt(gray_img, 0.5);
    
    switch p.Results.Method
        case 'custom_lsd'
            lines_matrix = customLSD(gray_img, ...
                'MinLength', p.Results.MinLength, ...
                'Sigma', p.Results.Sigma);
        case 'enhanced_hough'
            lines_matrix = enhancedHoughLines(gray_img, ...
                'MinLength', p.Results.MinLength, ...
                'Sigma', p.Results.Sigma);
        otherwise
            error('不支持的检测方法');
    end
    
    % 提取线段信息并合并角度相同且首尾相接的线段
    line_segments = extractLineInfo(lines_matrix);
    
    % 可视化
    % visualizeLineDetection(gray_img, line_segments, p.Results.Method);
end

function line_segments= extractLineInfo(lines_matrix)
    % 从线段矩阵提取信息
    line_segments = [];
    
    for k = 1:size(lines_matrix, 1)
        point1 = lines_matrix(k, 1:2);
        point2 = lines_matrix(k, 3:4);
        
        % 计算直线参数
        if point2(1) ~= point1(1)
            m = (point2(2) - point1(2)) / (point2(1) - point1(1));
            b = point1(2) - m * point1(1);
        else
            m = inf;
            b = point1(1);
        end
        
        % 计算长度和角度
        length_segment = norm(point2 - point1);
        dx = point2(1) - point1(1);
        dy = point2(2) - point1(2);
        angle = atan2d(dy, dx);
        
        line_segments(k).point1 = point1;
        line_segments(k).point2 = point2;
        line_segments(k).slope = m;
        line_segments(k).intercept = b;
        line_segments(k).length = length_segment;
        line_segments(k).angle = angle;
        line_segments(k).center = mean([point1; point2]);
    end

    % % 从中判断共线且首尾衔接的线段进行合并
    Angle_Threshold = 10.0;
    Pos_Threshold = 5.0;
    line_num = length(line_segments);
    combined_pair = [];
    for i = 1:line_num % 避免重复比较(i,j)和(j,i)
        for j = i + 1:line_num
            angle_diff = abs(mod(line_segments(i).angle - line_segments(j).angle + 180, 360) - 180);
            if angle_diff <= Angle_Threshold
                endpoints1 = [line_segments(i).point1; line_segments(i).point2];
                endpoints2 = [line_segments(j).point1; line_segments(j).point2];
                cross_dist = pdist2(endpoints1, endpoints2);
                [min_dist, min_idx] = min(cross_dist(:));
                if min_dist < Pos_Threshold %判断"两条线四个端点中，哪两个端点最近"
                    [close_idx1, close_idx2] = ind2sub([2, 2], min_idx);
                    P1_idx = 3 - close_idx1;
                    P2_idx = 3 - close_idx2;
                    combined_pair = [combined_pair;i, j, P1_idx, P2_idx];
                end
            end
        end
    end
    if ~isempty(combined_pair)
        line_combined = [];
        combined_num = size(combined_pair, 1);
        delete_indices = zeros(1, 2*combined_num);
        % fprintf(">> Combined lines: %d pairs\n", combined_num);
        for k = 1:size(combined_pair, 1)
            line1_idx = combined_pair(k,1);
            line1 = line_segments(line1_idx);
            switch combined_pair(k,3)
                case 1, line1_endpt = line1.point1;
                case 2, line1_endpt = line1.point2;
            end
            line2_idx = combined_pair(k,2);
            line2 = line_segments(line2_idx);
            switch combined_pair(k,4)
                case 1, line2_endpt = line2.point1;
                case 2, line2_endpt = line2.point2;
            end

            % combine two lines
            if line2_endpt(1) ~= line1_endpt(1)
                m = (line2_endpt(2) - line1_endpt(2)) / (line2_endpt(1) - line1_endpt(1));
                b = line1_endpt(2) - m * line1_endpt(1);
            else
                m = inf;
                b = line1_endpt(1);
            end
            line_combined(k).point1 = line1_endpt;
            line_combined(k).point2 = line2_endpt;
            line_combined(k).slope = m;
            line_combined(k).intercept = b;
            line_combined(k).length = norm(line2_endpt - line1_endpt);
            line_combined(k).angle = atan2d(line2_endpt(2) - line1_endpt(2), line2_endpt(1) - line1_endpt(1));
            line_combined(k).center = mean([line1_endpt; line2_endpt]);

            delete_indices(1, 2*k-1) = line1_idx;
            delete_indices(1, 2*k)   = line2_idx;
        end
        % delete original lines and add the combined ones.
        line_segments(delete_indices) = [];
        line_segments = [line_segments, line_combined];
        % fprintf(">> line_segments %d before.\n", line_num);
    end
end

function visualizeLineDetection(orig_img, line_segments, method_name)
    figure('Position', [100, 100, 1200, 400]);
    
    % 原图像
    subplot(1,2,1);
    imshow(orig_img);
    title('原图像');
    
    % 线段检测结果
    subplot(1,2,2);
    imshow(orig_img); hold on;
    
    for k = 1:length(line_segments)
        ls = line_segments(k);
        
        % 绘制线段
        plot([ls.point1(1), ls.point2(1)], ...
             [ls.point1(2), ls.point2(2)], ...
             'LineWidth', 2, 'Color', 'red');
        
        % 标记端点
        plot(ls.point1(1), ls.point1(2), 'o', ...
             'MarkerSize', 6, 'Color', 'green', 'MarkerFaceColor', 'green');
        plot(ls.point2(1), ls.point2(2), 's', ...
             'MarkerSize', 6, 'Color', 'blue', 'MarkerFaceColor', 'blue');
        text(ls.center(1), ls.center(2)-5, sprintf('%d', k), 'FontSize', 8, 'Color', 'red');
    end
    title(sprintf('%s方法检测结果 (%d条线段)', method_name, length(line_segments)));
end
