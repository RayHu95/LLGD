function lines = customLSD(gray_img, varargin)
    % 基于 Canny 边缘和方向一致性区域生长的线段检测。
    
    p = inputParser;
    addParameter(p, 'Sigma', 0.8, @isnumeric);
    addParameter(p, 'MinLength', 10, @isnumeric);
    addParameter(p, 'AngleTol', 10, @isnumeric);
    parse(p, varargin{:});
    
    edge_img = edge(gray_img, 'canny', [0.1 0.3], p.Results.Sigma);
    
    % Sobel 方向仅用于区域生长。
    [Gx, Gy] = imgradientxy(gray_img, 'sobel');
    [~, Gdir] = imgradient(Gx, Gy);
    
    % Canny 已包含非极大值抑制。
    thin_edges = edge_img;

    lines = lineSegmentDetection(thin_edges, Gdir, ...
        'MinLength', p.Results.MinLength, ...
        'AngleTol', p.Results.AngleTol);
end

function lines = lineSegmentDetection(edge_img, Gdir, varargin)
    p = inputParser;
    addParameter(p, 'MinLength', 10, @isnumeric);
    addParameter(p, 'AngleTol', 10, @isnumeric);
    parse(p, varargin{:});
    
    [rows, cols] = size(edge_img);
    visited = false(rows, cols);
    lines = [];
    
    [edge_y, edge_x] = find(edge_img);
    
    for i = 1:length(edge_x)
        x = edge_x(i);
        y = edge_y(i);
        if ~visited(y, x)
            line_points = growLineSegment(edge_img, visited, x, y, Gdir, ...
                p.Results.AngleTol);
            
            if size(line_points, 1) >= p.Results.MinLength
                [point1, point2] = fitLineEndpoints(line_points);
                lines = [lines; point1, point2];
                for j = 1: length(line_points)
                    visited(line_points(j,1), line_points(j,2)) = true;
                end
                
            end
        end
    end
end

function line_points = growLineSegment(edge_img, visited, start_x, start_y, Gdir, angle_tol)
    line_points = [start_y, start_x];
    visited(start_y, start_x) = true;
    
    start_angle = Gdir(start_y, start_x);
    
    queue = [start_y, start_x];
    while ~isempty(queue)
        current = queue(1,:);
        queue(1,:) = [];
        
        y = current(1);
        x = current(2);
        
        for dy = -1:1
            for dx = -1:1
                if dx == 0 && dy == 0
                    continue;
                end
                
                ny = y + dy;
                nx = x + dx;
                
                if ny >= 1 && ny <= size(edge_img,1) && nx >= 1 && nx <= size(edge_img,2)
                    if edge_img(ny, nx) && ~visited(ny, nx)
                        angle_diff = mod(Gdir(ny, nx) - start_angle + 90, 180) - 90;
                        
                        if abs(angle_diff) <= angle_tol
                            visited(ny, nx) = true;
                            line_points = [line_points; ny, nx];
                            queue = [queue; ny, nx];
                        end
                    end
                end
            end
        end
    end
end

function [point1, point2] = fitLineEndpoints(points)
    if size(points, 1) < 2
        point1 = points(1, [2,1]);
        point2 = point1;
        return;
    end
    
    [coeff, score] = pca(points);
    direction = coeff(:,1)';
    
    projected = points * direction';
    [~, min_idx] = min(projected);
    [~, max_idx] = max(projected);
    
    point1 = points(min_idx, [2,1]);
    point2 = points(max_idx, [2,1]);
end
