function lines = enhancedHoughLines(img, varargin)
    % 增强的霍夫变换线段检测
    
    p = inputParser;
    addParameter(p, 'MinLength', 20, @isnumeric);
    addParameter(p, 'FillGap', 10, @isnumeric);
    addParameter(p, 'Sigma', 1, @isnumeric);
    parse(p, varargin{:});
    
    % 转换为灰度
    if size(img, 3) == 3
        gray_img = rgb2gray(img);
    else
        gray_img = img;
    end
    
    % 边缘检测
    edge_img = edge(gray_img, 'canny', [], p.Results.Sigma);
    
    % 霍夫变换
    [H, theta, rho] = hough(edge_img);
    
    % 找到峰值
    peaks = houghpeaks(H, 100, 'Threshold', 0.1*max(H(:)));
    
    % 提取线段
    hough_lines = houghlines(edge_img, theta, rho, peaks, ...
        'FillGap', p.Results.FillGap, 'MinLength', p.Results.MinLength);
    
    % 转换为统一格式
    lines = [];
    for k = 1:length(hough_lines)
        point1 = hough_lines(k).point1;
        point2 = hough_lines(k).point2;
        lines = [lines; point1, point2];
    end
end