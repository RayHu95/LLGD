classdef ELiSeDDetector < handle
    % 基于 ELiSeD 的事件线段检测器。
    % 参考: "ELiSeD – An Event-Based Line Segment Detector" (Brändli et al.)
    
    properties (SetAccess = private)
        % 传感器尺寸
        sensorHeight
        sensorWidth
        
        % 检测器状态
        TL                % 最新时间戳图

        eventBuffer       % 圆形事件缓冲区 [buffer_size x 4]
        bufferIdx         % 下一写入位置
        bufferFull

        pixelToRegion     % 像素到支撑区域的映射
        supportRegions

        pixelToEventIndex % 各像素对应的事件行号
        pixelToBufferIndex
        
        % 参数
        bufferSize
        timestampCutoff
        angleTolerance
        minNeighbors
        minRegionSize
    end
    
    methods
        function obj = ELiSeDDetector(varargin)
            p = inputParser;
            addParameter(p, 'SensorSize', [180, 240], @(x) isnumeric(x) && numel(x)==2);
            addParameter(p, 'BufferSize', 4000, @isscalar);
            addParameter(p, 'TimestampCutoff', 50, @isscalar); % s
            addParameter(p, 'AngleToleranceDeg', 22.5, @isscalar);
            addParameter(p, 'MinNeighbors', 3, @isscalar);
            addParameter(p, 'MinRegionSize', 10, @isscalar);
            parse(p, varargin{:});
            
            sz = p.Results.SensorSize;
            obj.sensorHeight = sz(1);
            obj.sensorWidth = sz(2);
            
            obj.bufferSize = p.Results.BufferSize;
            obj.timestampCutoff = p.Results.TimestampCutoff;
            obj.angleTolerance = deg2rad(p.Results.AngleToleranceDeg);
            obj.minNeighbors = p.Results.MinNeighbors;
            obj.minRegionSize = p.Results.MinRegionSize;
            
            obj.TL = zeros(obj.sensorHeight, obj.sensorWidth) - inf;
            obj.eventBuffer = nan(obj.bufferSize, 4);
            obj.bufferIdx = 1;
            obj.bufferFull = false;
            obj.pixelToRegion = zeros(obj.sensorHeight, obj.sensorWidth);
            obj.pixelToBufferIndex = zeros(obj.sensorHeight, obj.sensorWidth, 'uint32');
            obj.supportRegions = {};
        end
        
        function validRegions = processEvents(obj, events)
            % 处理一组 [x, y, t, polarity] 事件。

            if isempty(events)
                validRegions = {};
                return;
            end

            obj.pixelToEventIndex = zeros(obj.sensorHeight, obj.sensorWidth, 'uint32');
            
            for i = 1:size(events, 1)
                ev = events(i, :);
                obj.updateWithEvent(ev, i);
            end

            [lineSegments, validRegions] = obj.fitLineSegments();
        end
    end
    
    methods (Access = private)
        function updateWithEvent(obj, ev, idx)
            x = round(ev(1)); y = round(ev(2)); t = ev(3);

            if ~(x >= 1 && x <= obj.sensorWidth && y >= 1 && y <= obj.sensorHeight)
                return;
            end

            if obj.bufferIdx > obj.bufferSize
                obj.bufferIdx = 1;
                obj.bufferFull = true;
            end

            if obj.bufferFull
                oldest_idx = obj.bufferIdx;
                oldest_ev = obj.eventBuffer(oldest_idx, :);
                ox = round(oldest_ev(1)); oy = round(oldest_ev(2));

                if ox >= 1 && ox <= obj.sensorWidth && ...
                        oy >= 1 && oy <= obj.sensorHeight && ...
                        obj.pixelToBufferIndex(oy, ox) == oldest_idx
                    obj.TL(oy, ox) = -inf;
                    old_region_id = obj.pixelToRegion(oy, ox);
                    if old_region_id > 0
                        obj.removePixelFromRegion(ox, oy, old_region_id);
                    end
                    obj.pixelToRegion(oy, ox) = 0;
                    obj.pixelToEventIndex(oy, ox) = 0;
                    obj.pixelToBufferIndex(oy, ox) = 0;
                end
            end

            obj.eventBuffer(obj.bufferIdx, :) = ev;
            obj.pixelToBufferIndex(y, x) = obj.bufferIdx;
            obj.bufferIdx = obj.bufferIdx + 1;
            
            obj.TL(y, x) = t;
            obj.pixelToEventIndex(y, x) = idx;
            
            omega = obj.computeOrientation(x, y, t);
            if isnan(omega)
                return;
            end
            
            candidates  = [x, y];
            candidate_regions = [];

            for dy = -1:1
                for dx = -1:1
                    if dx == 0 && dy == 0, continue; end
                    nx_i = x + dx; ny_i = y + dy;
                    if nx_i < 1 || nx_i > obj.sensorWidth || ny_i < 1 || ny_i > obj.sensorHeight
                        continue;
                    end
                    
                    if obj.TL(ny_i, nx_i) > (t - obj.timestampCutoff)
                        candidates(end+1, :) = [nx_i, ny_i];
                        region_id_n = obj.pixelToRegion(ny_i, nx_i);
                        if region_id_n > 0
                            region_omega = obj.supportRegions{region_id_n}.orientation;
                            angleDiff = mod(omega - region_omega + pi, 2*pi) - pi;
                            if abs(angleDiff) <= obj.angleTolerance
                                if ~ismember(region_id_n, candidate_regions)
                                    candidate_regions = [candidate_regions, region_id_n];
                                end
                            end
                        end
                    end
                end
            end
            
            current_region_id = obj.pixelToRegion(y, x);

            if ~isempty(candidate_regions)
                target_id = min(candidate_regions);

                if current_region_id > 0 && current_region_id ~= target_id
                    obj.removePixelFromRegion(x, y, current_region_id);
                    obj.pixelToRegion(y, x) = 0;
                end

                for i = 1:size(candidates, 1)
                    cx = candidates(i,1); cy = candidates(i,2);
                    old_id = obj.pixelToRegion(cy, cx);
                    if old_id ~= target_id
                        if old_id > 0
                            obj.removePixelFromRegion(cx, cy, old_id);
                        end
                        obj.addPixelToRegion(cx, cy, target_id, omega);
                    end
                end

            elseif size(candidates, 1) >= obj.minNeighbors
                if current_region_id == 0
                    new_id = length(obj.supportRegions) + 1;
                    obj.supportRegions{new_id} = struct('pixels', [], 'orientation', omega);
                    for i = 1:size(candidates, 1)
                        cx = candidates(i,1); cy = candidates(i,2);
                        obj.addPixelToRegion(cx, cy, new_id, omega);
                    end
                end
            end
        end
        
        function omega = computeOrientation(obj, x, y, t)
            omega = NaN;
            if x < 2 || x > obj.sensorWidth-1 || y < 2 || y > obj.sensorHeight-1
                return;
            end
            
            tl_block = obj.TL(y-1:y+1, x-1:x+1);
            tl_block(tl_block < (t - obj.timestampCutoff)) = NaN;
            
            if sum(~isnan(tl_block(:))) < 6
                return;
            end
            
            Gx = [-1 0 1; -2 0 2; -1 0 1];
            Gy = [-1 -2 -1; 0 0 0; 1 2 1];
            dx = sum(sum(Gx .* tl_block, 'omitnan'));
            dy = sum(sum(Gy .* tl_block, 'omitnan'));
            omega = atan2(dy, dx);
        end

        function addPixelToRegion(obj, x, y, region_id, omega)
            if x < 1 || x > obj.sensorWidth || y < 1 || y > obj.sensorHeight
                return;
            end
            obj.pixelToRegion(y, x) = region_id;
            obj.supportRegions{region_id}.pixels(end+1, :) = [x, y];
            % 使用最新支撑事件的方向。
            obj.supportRegions{region_id}.orientation = omega;
        end

        function removePixelFromRegion(obj, x, y, region_id)
            if region_id > length(obj.supportRegions)
                return;
            end
            reg = obj.supportRegions{region_id};
            idx_to_remove = find(reg.pixels(:,1) == x & reg.pixels(:,2) == y, 1);
            if ~isempty(idx_to_remove)
                reg.pixels(idx_to_remove, :) = [];
                obj.supportRegions{region_id} = reg;
            end
        end
        
        function [lineSegments, valid_regions] = fitLineSegments(obj)
            lineSegments = {};
            valid_regions = {};
            
            for r = 1:length(obj.supportRegions)
                reg = obj.supportRegions{r};
                if size(reg.pixels, 1) < obj.minRegionSize
                    continue;
                end

                eventIndices = [];
                valid_pixels = [];
                current_t = max(obj.eventBuffer(:,3), [], 'omitnan');
                for p = 1:size(reg.pixels, 1)
                    px = reg.pixels(p,1); py = reg.pixels(p,2);
                    eidx = obj.pixelToEventIndex(py, px);
                    if px >= 1 && px <= obj.sensorWidth && ...
                       py >= 1 && py <= obj.sensorHeight && ...
                       obj.TL(py, px) > (current_t - obj.timestampCutoff)
                        valid_pixels(end+1, :) = [px, py]; %#ok<AGROW>
                        eventIndices(end+1) = eidx; %#ok<AGROW>
                    end
                end
                
                if size(valid_pixels, 1) >= obj.minRegionSize
                    valid_regions{end+1} = struct('pixels', valid_pixels, 'orientation', reg.orientation, 'idx', eventIndices);
                end
            end
            
            for r = 1:length(valid_regions)
                pixels = valid_regions{r}.pixels;
                mu_x = mean(pixels(:,1));
                mu_y = mean(pixels(:,2));
                mu_20 = mean((pixels(:,1)-mu_x).^2);
                mu_02 = mean((pixels(:,2)-mu_y).^2);
                mu_11 = mean((pixels(:,1)-mu_x).*(pixels(:,2)-mu_y));
                
                theta = 0.5 * atan2(2*mu_11, mu_20 - mu_02);
                major_axis = [cos(theta), sin(theta)];
                proj = pixels * major_axis';
                [~, i1] = min(proj); [~, i2] = max(proj);
                seg = [pixels(i1,:); pixels(i2,:)];
                lineSegments{end+1} = seg;
            end
        end
    end
end
