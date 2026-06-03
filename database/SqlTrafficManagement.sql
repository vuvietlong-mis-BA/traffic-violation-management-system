CREATE DATABASE FINALGG
GO
USE FINALGG
GO

-- ===============================
-- 1. TẠO CẤU TRÚC CÁC BẢNG
-- ===============================
CREATE TABLE NguoiViPham (
    SoCCCD CHAR(12) NOT NULL PRIMARY KEY,
    HoVaTen NVARCHAR(100) NOT NULL,
    GioiTinh CHAR(7) CHECK (GioiTinh IN ('Nam' , 'Nu')) NOT NULL,
    DiaChi NVARCHAR(200) NOT NULL,
    SoDienThoai VARCHAR(15) NOT NULL,
    QuocTich NVARCHAR(25) NOT NULL
);

-----------------------------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE BangLaiXe (
    MaBLX VARCHAR(20) NOT NULL PRIMARY KEY,
    MaLoaiBang NVARCHAR(5) NOT NULL,
    NgayCap DATE NOT NULL,
    NgayHetHan DATE NOT NULL,
    DiemBLX TINYINT NOT NULL DEFAULT 12,
    SoCCCD CHAR(12) NOT NULL,
    FOREIGN KEY (SoCCCD) REFERENCES NguoiViPham(SoCCCD)
);
------------------------------------------------------------------------

CREATE TABLE PhuongTienGiaoThong (
    BienKiemSoat VARCHAR(12) NOT NULL PRIMARY KEY,
    LoaiPhuongTien NVARCHAR(10) NOT NULL,
    MauBien NVARCHAR(20) NOT NULL,
    SoCCCD CHAR(12) NOT NULL,
    FOREIGN KEY (SoCCCD) REFERENCES NguoiViPham(SoCCCD)
);

----------------------------------------------------------------------

CREATE TABLE LoiViPham (
    MaLoiViPham VARCHAR(20) NOT NULL PRIMARY KEY,
	LoaiPhuongTien NVARCHAR(10) NOT NULL,
	TenLoiViPham NVARCHAR(100) NOT NULL,
    MucPhatToiThieu INT NOT NULL,
    MucPhatToiDa INT NOT NULL,
    MucDiemTru TINYINT NOT NULL DEFAULT 0
);

-------------------------------------------------------------------

CREATE TABLE DonVi (
    MaDonVi VARCHAR(10) NOT NULL PRIMARY KEY,
    TenDonVi NVARCHAR(100) NOT NULL
); 

-----------------------------------------------------------------

CREATE TABLE LucLuongChucNang (
    SoHieu VARCHAR(10) NOT NULL PRIMARY KEY,
    HoVaTen NVARCHAR(100) NOT NULL,
    ChucVu NVARCHAR(50) NOT NULL,
    MaDonVi VARCHAR(10) NOT NULL,
    FOREIGN KEY (MaDonVi) REFERENCES DonVi(MaDonVi)
);

--------------------------------------------------------

CREATE TABLE BienBanViPham (
    MaBienBan VARCHAR(20) NOT NULL PRIMARY KEY,
    BienKiemSoat VARCHAR(12) NOT NULL,
    MaBLX VARCHAR(20),
    SoHieu VARCHAR(10) NOT NULL,
    ThoiGianViPham DATETIME NOT NULL,
    DiaDiemViPham NVARCHAR(200) NOT NULL,
    TrangThai NVARCHAR(50) NOT NULL,
    TongTienPhat INT NOT NULL DEFAULT 0,
    TongDiemPhat TINYINT NOT NULL DEFAULT 0,
    HanKhieuNai AS (DATEADD(day, 93, ThoiGianViPham)),
    HanNopPhat AS (DATEADD(day, 13, ThoiGianViPham)),
    NgayNopPhat DATETIME,
    FOREIGN KEY (MaBLX) REFERENCES BangLaiXe(MaBLX),
    FOREIGN KEY (BienKiemSoat) REFERENCES PhuongTienGiaoThong(BienKiemSoat),
    FOREIGN KEY (SoHieu) REFERENCES LucLuongChucNang(SoHieu)
);

------------------------------------------------------------------------------------------------

CREATE TABLE CTBienBanViPham (
    MaChiTiet VARCHAR(12) NOT NULL PRIMARY KEY,    
	MaBienBan VARCHAR(20) NOT NULL,
    MaLoiViPham VARCHAR(20) NOT NULL,
    MucTienPhat INT NOT NULL,
    FOREIGN KEY (MaBienBan) REFERENCES BienBanViPham(MaBienBan),
    FOREIGN KEY (MaLoiViPham) REFERENCES LoiViPham(MaLoiViPham)
);

----------------------------------------------------------------------------------------------------

CREATE TABLE DonKhieuNai (
    MaDonKhieuNai VARCHAR(20) NOT NULL PRIMARY KEY,
    SoCCCD CHAR(12) NOT NULL,
    HoVaTen NVARCHAR(100) NOT NULL,
    ThoiGianKhieuNai DATETIME NOT NULL,
    NoiDung NVARCHAR(500) NOT NULL,
	ThoiGianXuLy DATETIME,
    TrangThai NVARCHAR(50),
    MaBienBan VARCHAR(20) NOT NULL,
    SoHieu VARCHAR(10) NOT NULL,
    FOREIGN KEY (SoCCCD) REFERENCES NguoiViPham(SoCCCD),
    FOREIGN KEY (MaBienBan) REFERENCES BienBanViPham(MaBienBan),
    FOREIGN KEY (SoHieu) REFERENCES LucLuongChucNang(SoHieu)
);

-- ===============================
-- 2. TẠO TRIGGER
-- ===============================

 -- Tính tổng tiền phạt và tổng điểm phạt
CREATE TRIGGER [dbo].[trg_after_insert_ctbienban]
ON [dbo].[CTBienBanViPham]
AFTER INSERT
AS
BEGIN
    WITH ViolationsSummary AS (
        SELECT
            cbbvp.MaBienBan,
            SUM(ISNULL(cbbvp.MucTienPhat, 0)) AS TotalTienPhat,
            SUM(ISNULL(lv.MucDiemTru, 0)) AS TotalDiemPhat
        FROM CTBienBanViPham cbbvp
        JOIN LoiViPham lv ON cbbvp.MaLoiViPham = lv.MaLoiViPham
        WHERE cbbvp.MaBienBan IN (SELECT MaBienBan FROM INSERTED)
        GROUP BY cbbvp.MaBienBan
    )
    UPDATE bbp
    SET TongTienPhat = vs.TotalTienPhat,
        TongDiemPhat = vs.TotalDiemPhat
    FROM dbo.BienBanViPham bbp
    INNER JOIN ViolationsSummary vs ON bbp.MaBienBan = vs.MaBienBan;
END;
GO

----------------------------------------------------------------

-- Cập nhật trạng thái "Danop/noptre" 

CREATE TRIGGER trg_after_update_trangthai
ON BienBanViPham
AFTER UPDATE
AS
BEGIN
    -- Cập nhật trạng thái "Danop" nếu nộp đúng hạn
    UPDATE BienBanViPham
    SET TrangThai = 'Danop'
    FROM BienBanViPham BB
    INNER JOIN INSERTED i ON BB.MaBienBan = i.MaBienBan
    WHERE i.NgayNopPhat IS NOT NULL 
          AND i.NgayNopPhat <= i.HanNopPhat;

    -- Cập nhật trạng thái "Noptre X ngay" và tính lại tổng tiền phạt nếu nộp trễ
    UPDATE BienBanViPham
    SET TongTienPhat = i.TongTienPhat + (i.TongTienPhat * 0.0005 * DATEDIFF(day, i.HanNopPhat, i.NgayNopPhat)),
        TrangThai = CONCAT('Noptre ', DATEDIFF(day, i.HanNopPhat, i.NgayNopPhat), ' ngay')
    FROM BienBanViPham BB
    INNER JOIN INSERTED i ON BB.MaBienBan = i.MaBienBan
    WHERE i.NgayNopPhat IS NOT NULL 
          AND i.NgayNopPhat > i.HanNopPhat;
END;
GO

------------- bvb -----------------------------------------------------------------------

 -- Cập nhật điểm bằng lái xe dựa trên tổng điểm phạt

CREATE TRIGGER trg_UpdateDiemBLX
ON BienBanViPham
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE BangLaiXe
    SET DiemBLX = GREATEST(0, 12 - TongDiem.TongDiemPhat)
    FROM BangLaiXe
    INNER JOIN (
        SELECT Mablx, SUM(TongDiemPhat) AS TongDiemPhat
        FROM BienBanViPham
        GROUP BY MaBLX
    ) AS TongDiem ON BangLaiXe.MaBLX = TongDiem.MaBLX;
END;
GO

------------------------------------------------------------------------------------------

-- Trigger phục hồi điểm khi khiếu nại thành công 

CREATE TRIGGER trg_RestoreDiemBLX
ON DonKhieuNai
AFTER UPDATE
AS
BEGIN
    -- Khai báo các biến để lưu trữ thông tin cập nhật
    DECLARE @TrangThai NVARCHAR(50), @MaBienBan VARCHAR(20), @SoCCCD CHAR(12);
    
    -- Lấy các giá trị đã cập nhật
    SELECT @TrangThai = TrangThai, @MaBienBan = MaBienBan, @SoCCCD = SoCCCD
    FROM inserted;
    
    -- Kiểm tra nếu khiếu nại đã được xử lý thành công
    IF @TrangThai = 'Khieu nai thanh cong'
    BEGIN

	
        -- Cập nhật trạng thái của biên bản vi phạm thành 'Đã hủy'
        UPDATE BienBanViPham
        SET TrangThai = 'Dahuy'
        WHERE MaBienBan = @MaBienBan;

        -- Phục hồi điểm cho tài xế (nếu khiếu nại thành công)
        UPDATE BangLaiXe
        SET DiemBLX = 
            CASE 
                WHEN (BienBanViPham.TongDiemPhat + BangLaiXe.DiemBLX) > 12 THEN 12
                ELSE (BienBanViPham.TongDiemPhat + BangLaiXe.DiemBLX)
            END
        FROM BangLaiXe
        JOIN BienBanViPham ON BangLaiXe.MaBLX = BienBanViPham.MaBLX
        WHERE BienBanViPham.TrangThai = 'Dahuy' ;

		   UPDATE DonKhieuNai
    SET ThoiGianXuLy = SYSDATETIME()
    FROM DonKhieuNai dkn
    JOIN INSERTED i ON dkn.MaDonKhieuNai = i.MaDonKhieuNai
    WHERE i.TrangThai = 'Khieu nai thanh cong';

        PRINT 'Diem da duoc hoi phuc va bien ban da duoc huy: ' + @SoCCCD;
    END
END;
GO
----------------------------------------------------------------------------------------------

-- ===============================
-- 3. THÊM DỮ LIỆU MẪU
-- ===============================

INSERT INTO NguoiViPham (SoCCCD, HoVaTen, GioiTinh, DiaChi, SoDienThoai, QuocTich) VALUES
('001201000001', N'Nguyen Van A', N'Nam', N'123 Pho Hue, Q.Hai Ba Trung, Ha Noi', '0911000001', N'Viet Nam'),
('001201000002', N'Tran Thi B', N'Nu', N'456 Duong Lang, Q.Dong Da, Ha Noi', '0911000002', N'Viet Nam'),
('001201000003', N'Le Van C', N'Nam', N'789 Pho Vong, Q.Hai Ba Trung, Ha Noi', '0911000003', N'Viet Nam'),
('001201000004', N'Pham Thi D', N'Nu', N'321 Pho Bach Mai, Q.Hai Ba Trung, Ha Noi', '0911000004', N'Viet Nam'),
('001201000005', N'Hoang Van E', N'Nam', N'654 Duong Kim Ma, Q.Ba Dinh, Ha Noi', '0911000005', N'Viet Nam'),
('001201000006', N'Vu Thi F', N'Nu', N'987 Pho Xuan Thuy, Q.Cau Giay, Ha Noi', '0911000006', N'Viet Nam'),
('001201000007', N'Dang Van G', N'Nam', N'147 Duong Nguyen Trai, Q.Thanh Xuan, Ha Noi', '0911000007', N'Viet Nam'),
('001201000008', N'Bui Thi H', N'Nu', N'258 Pho Chua Boc, Q.Dong Da, Ha Noi', '0911000008', N'Viet Nam'),
('001201000009', N'Do Van I', N'Nam', N'369 Duong Giai Phong, Q.Hoang Mai, Ha Noi', '0911000009', N'Viet Nam'),
('001201000010', N'Ngo Thi K', N'Nu', N'159 Pho Tran Duy Hung, Q.Cau Giay, Ha Noi', '0911000010', N'Viet Nam'),
('001201000011', N'Ly Van L', N'Nam', N'753 Duong Nguyen Chi Thanh, Q.Ba Dinh, Ha Noi', '0911000011', N'Viet Nam'),
('001201000012', N'Trinh Thi M', N'Nu', N'951 Pho Lieu Giai, Q.Ba Dinh, Ha Noi', '0911000012', N'Viet Nam'),
('001201000013', N'Phan Van N', N'Nam', N'852 Duong Hoang Quoc Viet, Q.Cau Giay, Ha Noi', '0911000013', N'Viet Nam'),
('001201000014', N'Vu Thi O', N'Nu', N'456 Pho Minh Khai, Q.Bac Tu Liem, Ha Noi', '0911000014', N'Viet Nam'),
('001201000015', N'Ho Van P', N'Nam', N'753 Duong Pham Hung, Q.Nam Tu Liem, Ha Noi', '0911000015', N'Viet Nam'),
('001201000016', N'Dinh Thi Q', N'Nu', N'159 Pho Xa Dan, Q.Dong Da, Ha Noi', '0911000016', N'Viet Nam'),
('001201000017', N'Nguyen Van R', N'Nam', N'357 Duong La Thanh, Q.Ba Dinh, Ha Noi', '0911000017', N'Viet Nam'),
('001201000018', N'Tran Thi S', N'Nu', N'753 Pho Nguyen Khang, Q.Cau Giay, Ha Noi', '0911000018', N'Viet Nam'),
('001201000019', N'Le Van T', N'Nam', N'852 Duong Khuat Duy Tien, Q.Thanh Xuan, Ha Noi', '0911000019', N'Viet Nam'),
('001201000020', N'Pham Thi U', N'Nu', N'456 Pho Trung Kinh, Q.Cau Giay, Ha Noi', '0911000020', N'Viet Nam'),
('001201000021', N'Hoang Van V', N'Nam', N'753 Duong Le Van Luong, Q.Nam Tu Liem, Ha Noi', '0911000021', N'Viet Nam'),
('001201000022', N'Vu Thi X', N'Nu', N'159 Pho Hoang Ngan, Q.Cau Giay, Ha Noi', '0911000022', N'Viet Nam'),
('001201000023', N'Dang Van Y', N'Nam', N'357 Duong Nguyen Van Huyen, Q.Cau Giay, Ha Noi', '0911000023', N'Viet Nam'),
('001201000024', N'Bui Thi Z', N'Nu', N'753 Pho Hoang Quoc Viet, Q.Bac Tu Liem, Ha Noi', '0911000024', N'Viet Nam'),
('001201000025', N'Do Van AA', N'Nam', N'852 Duong Pham Van Dong, Q.Bac Tu Liem, Ha Noi', '0911000025', N'Viet Nam'),
('001201000026', N'Ngo Thi AB', N'Nu', N'456 Pho Ho Tung Mau, Q.Bac Tu Liem, Ha Noi', '0911000026', N'Viet Nam'),
('001201000027', N'Ly Van AC', N'Nam', N'753 Duong Co Nhue, Q.Bac Tu Liem, Ha Noi', '0911000027', N'Viet Nam'),
('001201000028', N'Trinh Thi AD', N'Nu', N'159 Pho Doi Can, Q.Ba Dinh, Ha Noi', '0911000028', N'Viet Nam'),
('001201000029', N'Phan Van AE', N'Nam', N'357 Duong Nguyen Thai Hoc, Q.Ba Dinh, Ha Noi', '0911000029', N'Viet Nam'),
('001201000030', N'Vu Thi AF', N'Nu', N'753 Pho Kim Ma, Q.Ba Dinh, Ha Noi', '0911000030', N'Viet Nam'),
('001201000031', N'Ho Van AG', N'Nam', N'852 Duong Nguyen Du, Q.Hai Ba Trung, Ha Noi', '0911000031', N'Viet Nam'),
('001201000032', N'Dinh Thi AH', N'Nu', N'456 Pho Tran Hung Dao, Q.Hoan Kiem, Ha Noi', '0911000032', N'Viet Nam'),
('001201000033', N'Nguyen Van AI', N'Nam', N'753 Duong Hang Bai, Q.Hoan Kiem, Ha Noi', '0911000033', N'Viet Nam'),
('001201000034', N'Tran Thi AJ', N'Nu', N'159 Pho Hang Gai, Q.Hoan Kiem, Ha Noi', '0911000034', N'Viet Nam'),
('001201000035', N'Le Van AK', N'Nam', N'357 Duong Hang Dao, Q.Hoan Kiem, Ha Noi', '0911000035', N'Viet Nam'),
('001201000036', N'Pham Thi AL', N'Nu', N'753 Pho Hang Duong, Q.Hoan Kiem, Ha Noi', '0911000036', N'Viet Nam'),
('001201000037', N'Hoang Van AM', N'Nam', N'852 Duong Hang Ma, Q.Hoan Kiem, Ha Noi', '0911000037', N'Viet Nam'),
('001201000038', N'Vu Thi AN', N'Nu', N'456 Pho Hang Bac, Q.Hoan Kiem, Ha Noi', '0911000038', N'Viet Nam'),
('001201000039', N'Dang Van AO', N'Nam', N'753 Duong Hang Bo, Q.Hoan Kiem, Ha Noi', '0911000039', N'Viet Nam'),
('001201000040', N'Bui Thi AP', N'Nu', N'159 Pho Hang Buom, Q.Hoan Kiem, Ha Noi', '0911000040', N'Viet Nam'),
('001201000041', N'Do Van AQ', N'Nam', N'357 Duong Hang Chieu, Q.Hoan Kiem, Ha Noi', '0911000041', N'Viet Nam'),
('001201000042', N'Ngo Thi AR', N'Nu', N'753 Pho Hang Cot, Q.Hoan Kiem, Ha Noi', '0911000042', N'Viet Nam'),
('001201000043', N'Ly Van AS', N'Nam', N'852 Duong Hang Da, Q.Hoan Kiem, Ha Noi', '0911000043', N'Viet Nam'),
('001201000044', N'Trinh Thi AT', N'Nu', N'456 Pho Hang Dao, Q.Hoan Kiem, Ha Noi', '0911000044', N'Viet Nam'),
('001201000045', N'Phan Van AU', N'Nam', N'753 Duong Hang Dieu, Q.Hoan Kiem, Ha Noi', '0911000045', N'Viet Nam'),
('001201000046', N'Vu Thi AV', N'Nu', N'159 Pho Hang Ga, Q.Hoan Kiem, Ha Noi', '0911000046', N'Viet Nam'),
('001201000047', N'Ho Van AW', N'Nam', N'357 Duong Hang Giay, Q.Hoan Kiem, Ha Noi', '0911000047', N'Viet Nam'),
('001201000048', N'Dinh Thi AX', N'Nu', N'753 Pho Hang Hanh, Q.Hoan Kiem, Ha Noi', '0911000048', N'Viet Nam'),
('001201000049', N'Nguyen Van AY', N'Nam', N'852 Duong Hang Hom, Q.Hoan Kiem, Ha Noi', '0911000049', N'Viet Nam'),
('001201000050', N'Tran Thi AZ', N'Nu', N'456 Pho Hang Khay, Q.Hoan Kiem, Ha Noi', '0911000050', N'Viet Nam'),
('001201000051', N'Le Van BA', N'Nam', N'753 Duong Hang Luoc, Q.Hoan Kiem, Ha Noi', '0911000051', N'Viet Nam'),
('001201000052', N'Pham Thi BB', N'Nu', N'159 Pho Hang Ma, Q.Hoan Kiem, Ha Noi', '0911000052', N'Viet Nam'),
('001201000053', N'Hoang Van BC', N'Nam', N'357 Duong Hang Mam, Q.Hoan Kiem, Ha Noi', '0911000053', N'Viet Nam'),
('001201000054', N'Vu Thi BD', N'Nu', N'753 Pho Hang Muoi, Q.Hoan Kiem, Ha Noi', '0911000054', N'Viet Nam'),
('001201000055', N'Dang Van BE', N'Nam', N'852 Duong Hang Ngang, Q.Hoan Kiem, Ha Noi', '0911000055', N'Viet Nam'),
('001201000056', N'Bui Thi BF', N'Nu', N'456 Pho Hang Phe, Q.Hoan Kiem, Ha Noi', '0911000056', N'Viet Nam'),
('001201000057', N'Do Van BG', N'Nam', N'753 Duong Hang Quat, Q.Hoan Kiem, Ha Noi', '0911000057', N'Viet Nam'),
('001201000058', N'Ngo Thi BH', N'Nu', N'159 Pho Hang Ruoi, Q.Hoan Kiem, Ha Noi', '0911000058', N'Viet Nam'),
('001201000059', N'Ly Van BI', N'Nam', N'357 Duong Hang Thiec, Q.Hoan Kiem, Ha Noi', '0911000059', N'Viet Nam'),
('001201000060', N'Trinh Thi BJ', N'Nu', N'753 Pho Hang Thung, Q.Hoan Kiem, Ha Noi', '0911000060', N'Viet Nam'),
('001201000061', N'Phan Van BK', N'Nam', N'852 Duong Hang Tre, Q.Hoan Kiem, Ha Noi', '0911000061', N'Viet Nam'),
('001201000062', N'Vu Thi BL', N'Nu', N'456 Pho Hang Trong, Q.Hoan Kiem, Ha Noi', '0911000062', N'Viet Nam'),
('001201000063', N'Ho Van BM', N'Nam', N'753 Duong Hang Vai, Q.Hoan Kiem, Ha Noi', '0911000063', N'Viet Nam'),
('001201000064', N'Dinh Thi BN', N'Nu', N'159 Pho Lo Duc, Q.Hai Ba Trung, Ha Noi', '0911000064', N'Viet Nam'),
('001201000065', N'Nguyen Van BO', N'Nam', N'357 Duong Bui Thi Xuan, Q.Hai Ba Trung, Ha Noi', '0911000065', N'Viet Nam'),
('001201000066', N'Tran Thi BP', N'Nu', N'753 Pho Tran Nhan Tong, Q.Hai Ba Trung, Ha Noi', '0911000066', N'Viet Nam'),
('001201000067', N'Le Van BQ', N'Nam', N'852 Duong Nguyen Cong Tru, Q.Hai Ba Trung, Ha Noi', '0911000067', N'Viet Nam'),
('001201000068', N'Pham Thi BR', N'Nu', N'456 Pho Quang Trung, Q.Hai Ba Trung, Ha Noi', '0911000068', N'Viet Nam'),
('001201000069', N'Hoang Van BS', N'Nam', N'753 Duong Tran Khat Chan, Q.Hai Ba Trung, Ha Noi', '0911000069', N'Viet Nam'),
('001201000070', N'Vu Thi BT', N'Nu', N'159 Pho Mai Hac De, Q.Hai Ba Trung, Ha Noi', '0911000070', N'Viet Nam'),
('001201000071', N'Dang Van BU', N'Nam', N'357 Duong Nguyen Dinh Chieu, Q.Hai Ba Trung, Ha Noi', '0911000071', N'Viet Nam'),
('001201000072', 'Tran Thi BR', 'Nu', '753 Pho Nguyen Khang, Q.Cau Giay, Ha Noi', '0911000089', 'Viet Nam'),
('001201000073', 'Le Van BS', 'Nam', '852 Duong Khuat Duy Tien, Q.Thanh Xuan, Ha Noi', '0911000090', 'Viet Nam'),
('001201000074', 'Pham Thi BT', 'Nu', '456 Pho Trung Kinh, Q.Cau Giay, Ha Noi', '0911000091', 'Viet Nam');
--------------------------------------------------------------------------------------------------------------------------------

INSERT INTO BangLaiXe (MaBLX, MaLoaiBang, NgayCap, NgayHetHan, DiemBLX, SoCCCD) VALUES
-- Người có cả 2 bằng A1 và B1 (20 người)
-- Người có cả bằng A1 và B1 (20 người đầu)
('BLXHN0001', N'A1', '2020-01-15', '2030-01-15', 12, '001201000001'),
('BLXHN0002', N'B1', '2021-03-10', '2030-03-10', 12, '001201000001'),
('BLXHN0003', N'A1', '2019-05-20', '2030-05-20', 12, '001201000002'),
('BLXHN0004', N'B1', '2022-07-05', '2030-07-05', 12, '001201000002'),
('BLXHN0005', N'A1', '2021-02-18', '2030-02-18', 12, '001201000003'),
('BLXHN0006', N'B1', '2020-08-12', '2030-08-12', 12, '001201000003'),
('BLXHN0007', N'A1', '2022-04-22', '2030-04-22', 12, '001201000004'),
('BLXHN0008', N'B1', '2021-10-30', '2030-10-30', 12, '001201000004'),
('BLXHN0009', N'A1', '2020-11-30', '2030-11-30', 12, '001201000005'),
('BLXHN0010', N'B1', '2019-09-25', '2030-09-25', 12, '001201000005'),
('BLXHN0011', N'A1', '2021-12-15', '2030-12-15', 12, '001201000006'),
('BLXHN0012', N'B1', '2020-10-20', '2030-10-20', 12, '001201000006'),
('BLXHN0013', N'A1', '2019-07-10', '2030-07-10', 12, '001201000007'),
('BLXHN0014', N'B1', '2022-01-25', '2030-01-25', 12, '001201000007'),
('BLXHN0015', N'A1', '2021-05-30', '2030-05-30', 12, '001201000008'),
('BLXHN0016', N'B1', '2020-03-15', '2030-03-15', 12, '001201000008'),
('BLXHN0017', N'A1', '2019-11-20', '2030-11-20', 12, '001201000009'),
('BLXHN0018', N'B1', '2022-06-10', '2030-06-10', 12, '001201000009'),
('BLXHN0019', N'A1', '2021-08-05', '2030-08-05', 12, '001201000010'),
('BLXHN0020', N'B1', '2020-04-18', '2030-04-18', 12, '001201000010'),

-- Người chỉ có bằng A1 (30 người)
('BLXHN0021', N'A1', '2020-02-14', '2030-02-14', 12, '001201000011'),
('BLXHN0022', N'A1', '2021-04-25', '2030-04-25', 12, '001201000012'),
('BLXHN0023', N'A1', '2019-06-30', '2030-06-30', 12, '001201000013'),
('BLXHN0024', N'A1', '2022-03-15', '2030-03-15', 12, '001201000014'),
('BLXHN0025', N'A1', '2020-07-20', '2030-07-20', 12, '001201000015'),
('BLXHN0026', N'A1', '2021-09-10', '2030-09-10', 12, '001201000016'),
('BLXHN0027', N'A1', '2019-12-05', '2030-12-05', 12, '001201000017'),
('BLXHN0028', N'A1', '2022-05-18', '2030-05-18', 12, '001201000018'),
('BLXHN0029', N'A1', '2020-08-22', '2030-08-22', 12, '001201000019'),
('BLXHN0030', N'A1', '2021-10-30', '2030-10-30', 12, '001201000020'),
('BLXHN0031', N'A1', '2019-01-15', '2030-01-15', 12, '001201000021'),
('BLXHN0032', N'A1', '2022-02-20', '2030-02-20', 12, '001201000022'),
('BLXHN0033', N'A1', '2020-05-25', '2030-05-25', 12, '001201000023'),
('BLXHN0034', N'A1', '2021-07-30', '2030-07-30', 12, '001201000024'),
('BLXHN0035', N'A1', '2019-10-10', '2030-10-10', 12, '001201000025'),
('BLXHN0036', N'A1', '2022-01-05', '2030-01-05', 12, '001201000026'),
('BLXHN0037', N'A1', '2020-03-18', '2030-03-18', 12, '001201000027'),
('BLXHN0038', N'A1', '2021-06-22', '2030-06-22', 12, '001201000028'),
('BLXHN0039', N'A1', '2019-08-30', '2030-08-30', 12, '001201000029'),
('BLXHN0040', N'A1', '2022-04-15', '2030-04-15', 12, '001201000030'),
('BLXHN0041', N'A1', '2020-09-20', '2030-09-20', 12, '001201000031'),
('BLXHN0042', N'A1', '2021-11-10', '2030-11-10', 12, '001201000032'),
('BLXHN0043', N'A1', '2019-02-05', '2030-02-05', 12, '001201000033'),
('BLXHN0044', N'A1', '2022-07-18', '2030-07-18', 12, '001201000034'),
('BLXHN0045', N'A1', '2020-10-22', '2030-10-22', 12, '001201000035'),
('BLXHN0046', N'A1', '2021-12-30', '2030-12-30', 12, '001201000036'),
('BLXHN0047', N'A1', '2019-03-15', '2030-03-15', 12, '001201000037'),
('BLXHN0048', N'A1', '2022-05-20', '2030-05-20', 12, '001201000038'),
('BLXHN0049', N'A1', '2020-06-25', '2030-06-25', 12, '001201000039'),
('BLXHN0050', N'A1', '2021-08-30', '2030-08-30', 12, '001201000040'),

-- Người chỉ có bằng B1 (31 người)
('BLXHN0051', N'B1', '2020-01-10', '2030-01-10', 12, '001201000041'),
('BLXHN0052', N'B1', '2021-02-15', '2030-02-15', 12, '001201000042'),
('BLXHN0053', N'B1', '2019-04-20', '2030-04-20', 12, '001201000043'),
('BLXHN0054', N'B1', '2022-03-10', '2030-03-10', 12, '001201000044'),
('BLXHN0055', N'B1', '2020-05-15', '2030-05-15', 12, '001201000045'),
('BLXHN0056', N'B1', '2021-07-20', '2030-07-20', 12, '001201000046'),
('BLXHN0057', N'B1', '2019-09-25', '2030-09-25', 12, '001201000047'),
('BLXHN0058', N'B1', '2022-04-05', '2030-04-05', 12, '001201000048'),
('BLXHN0059', N'B1', '2020-08-10', '2030-08-10', 12, '001201000049'),
('BLXHN0060', N'B1', '2021-10-15', '2030-10-15', 12, '001201000050'),
('BLXHN0061', N'B1', '2019-12-20', '2030-12-20', 12, '001201000051'),
('BLXHN0062', N'B1', '2022-01-10', '2030-01-10', 12, '001201000052'),
('BLXHN0063', N'B1', '2020-02-15', '2030-02-15', 12, '001201000053'),
('BLXHN0064', N'B1', '2021-04-20', '2030-04-20', 12, '001201000054'),
('BLXHN0065', N'B1', '2019-06-25', '2030-06-25', 12, '001201000055'),
('BLXHN0066', N'B1', '2022-05-10', '2030-05-10', 12, '001201000056'),
('BLXHN0067', N'B1', '2020-07-15', '2030-07-15', 12, '001201000057'),
('BLXHN0068', N'B1', '2021-09-20', '2030-09-20', 12, '001201000058'),
('BLXHN0069', N'B1', '2019-11-25', '2030-11-25', 12, '001201000059'),
('BLXHN0070', N'B1', '2022-06-05', '2030-06-05', 12, '001201000060'),
('BLXHN0071', N'B1', '2020-08-10', '2030-08-10', 12, '001201000061'),
('BLXHN0072', N'B1', '2021-10-15', '2030-10-15', 12, '001201000062'),
('BLXHN0073', N'B1', '2019-12-20', '2030-12-20', 12, '001201000063'),
('BLXHN0074', N'B1', '2022-01-10', '2030-01-10', 12, '001201000064'),
('BLXHN0075', N'B1', '2020-03-15', '2030-03-15', 12, '001201000065'),
('BLXHN0076', N'B1', '2021-05-20', '2030-05-20', 12, '001201000066'),
('BLXHN0077', N'B1', '2019-07-25', '2030-07-25', 12, '001201000067'),
('BLXHN0078', N'B1', '2022-04-05', '2030-04-05', 12, '001201000068'),
('BLXHN0079', N'B1', '2020-06-10', '2030-06-10', 12, '001201000069'),
('BLXHN0080', N'B1', '2021-08-15', '2030-08-15', 12, '001201000070'),
('BLXHN0081', N'B1', '2019-10-20', '2030-10-20', 12, '001201000071');

-----------------------------------------------------------------------------

INSERT INTO PhuongTienGiaoThong (BienKiemSoat, LoaiPhuongTien, MauBien, SoCCCD) VALUES
-- 20 người có cả ô tô và xe máy
('29A1-0001', N'Xe may', N'Trang', '001201000001'),
('29A2-0001', N'O to', N'Trang', '001201000001'),
('29B1-0002', N'Xe may', N'Trang ', '001201000002'),
('29B2-0002', N'O to', N'Trang', '001201000002'),
('29C1-0003', N'Xe may', N'Trang ', '001201000003'),
('29C2-0003', N'O to', N'Trang', '001201000003'),
('29D1-0004', N'Xe may', N'Trang', '001201000004'),
('29D2-0004', N'O to', N'Trang', '001201000004'),
('29E1-0005', N'Xe may', N'Trang', '001201000005'),
('29E2-0005', N'O to', N'Trang', '001201000005'),
('29F1-0006', N'Xe may', N'Trang', '001201000006'),
('29F2-0006', N'O to', N'Trang', '001201000006'),
('29G1-0007', N'Xe may', N'Trang', '001201000007'),
('29G2-0007', N'O to', N'Trang', '001201000007'),
('29H1-0008', N'Xe may', N'Trang', '001201000008'),
('29H2-0008', N'O to', N'Trang', '001201000008'),
('29K1-0009', N'Xe may', N'Trang', '001201000009'),
('29K2-0009', N'O to', N'Trang', '001201000009'),
('29L1-0010', N'Xe may', N'Trang', '001201000010'),
('29L2-0010', N'O to', N'Trang', '001201000010'),
('29M1-0011', N'Xe may', N'Trang', '001201000011'),
('29M2-0011', N'O to', N'Trang', '001201000011'),
('29N1-0012', N'Xe may', N'Trang', '001201000012'),
('29N2-0012', N'O to', N'Trang', '001201000012'),
('29P1-0013', N'Xe may', N'Trang', '001201000013'),
('29P2-0013', N'O to', N'Trang', '001201000013'),
('29Q1-0014', N'Xe may', N'Trang', '001201000014'),
('29Q2-0014', N'O to', N'Trang', '001201000014'),
('29R1-0015', N'Xe may', N'Trang', '001201000015'),
('29R2-0015', N'O to', N'Trang', '001201000015'),
('29S1-0016', N'Xe may', N'Trang', '001201000016'),
('29S2-0016', N'O to', N'Trang', '001201000016'),
('29T1-0017', N'Xe may', N'Trang', '001201000017'),
('29T2-0017', N'O to', N'Trang', '001201000017'),
('29U1-0018', N'Xe may', N'Trang', '001201000018'),
('29U2-0018', N'O to', N'Trang', '001201000018'),
('29V1-0019', N'Xe may', N'Trang', '001201000019'),
('29V2-0019', N'O to', N'Trang', '001201000019'),
('29X1-0020', N'Xe may', N'Trang', '001201000020'),
('29X2-0020', N'O to', N'Trang xanh','001201000020'),

-- 30 người chỉ có xe máy
('30A1-0021', N'Xe may', N'Trang', '001201000021'),
('30B1-0022', N'Xe may', N'Trang', '001201000022'),
('30C1-0023', N'Xe may', N'Trang', '001201000023'),
('30D1-0024', N'Xe may', N'Trang', '001201000024'),
('30E1-0025', N'Xe may', N'Trang', '001201000025'),
('30F1-0026', N'Xe may', N'Trang', '001201000026'),
('30G1-0027', N'Xe may', N'Trang', '001201000027'),
('30H1-0028', N'Xe may', N'Trang', '001201000028'),
('30K1-0029', N'Xe may', N'Trang', '001201000029'),
('30L1-0030', N'Xe may', N'Trang', '001201000030'),
('30M1-0031', N'Xe may', N'Trang', '001201000031'),
('30N1-0032', N'Xe may', N'Trang', '001201000032'),
('30P1-0033', N'Xe may', N'Trang', '001201000033'),
('30Q1-0034', N'Xe may', N'Trang', '001201000034'),
('30R1-0035', N'Xe may', N'Trang xanh', '001201000035'),
('30S1-0036', N'Xe may', N'Trang xanh', '001201000036'),
('30T1-0037', N'Xe may', N'Trang xanh', '001201000037'),
('30U1-0038', N'Xe may', N'Trang xanh', '001201000038'),
('30V1-0039', N'Xe may', N'Trang', '001201000039'),
('30X1-0040', N'Xe may', N'Trang', '001201000040'),
('30Y1-0041', N'Xe may', N'Trang', '001201000041'),
('30Z1-0042', N'Xe may', N'Trang', '001201000042'),
('31A1-0043', N'Xe may', N'Trang', '001201000043'),
('31B1-0044', N'Xe may', N'Trang', '001201000044'),
('31C1-0045', N'Xe may', N'Trang', '001201000045'),
('31D1-0046', N'Xe may', N'Trang', '001201000046'),
('31E1-0047', N'Xe may', N'Trang', '001201000047'),
('31F1-0048', N'Xe may', N'Trang', '001201000048'),
('31G1-0049', N'Xe may', N'Trang', '001201000049'),
('31H1-0050', N'Xe may', N'Trang', '001201000050'),

-- 21 người chỉ có ô tô
('32A2-0051', N'O to', N'Trang', '001201000051'),
('32B2-0052', N'O to', N'Trang', '001201000052'),
('32C2-0053', N'O to', N'Trang', '001201000053'),
('32D2-0054', N'O to', N'Trang', '001201000054'),
('32E2-0055', N'O to', N'Trang', '001201000055'),
('32F2-0056', N'O to', N'Trang', '001201000056'),
('32G2-0057', N'O to', N'Trang', '001201000057'),
('32H2-0058', N'O to', N'Trang', '001201000058'),
('32K2-0059', N'O to', N'Trang', '001201000059'),
('32L2-0060', N'O to', N'Trang', '001201000060'),
('32M2-0061', N'O to', N'Trang', '001201000061'),
('32N2-0062', N'O to', N'Trang', '001201000062'),
('32P2-0063', N'O to', N'Trang', '001201000063'),
('32Q2-0064', N'O to', N'Trang', '001201000064'),
('32R2-0065', N'O to', N'Trang', '001201000065'),
('32S2-0066', N'O to', N'Trang', '001201000066'),
('32T2-0067', N'O to', N'Trang', '001201000067'),
('32U2-0068', N'O to', N'Trang', '001201000068'),
('32V2-0069', N'O to', N'Trang', '001201000069'),
('32X2-0070', N'O to', N'Trang xanh', '001201000070'),
('32Y2-0071', N'O to', N'Trang xanh', '001201000071'),
('33U1-0089', N'O to', 'Trang', '001201000072'),
('33V1-0090', N'O to', 'Trang', '001201000073'),
('33X1-0091', N'O to', 'Trang', '001201000074');

----------------------------------------------------------------------------------------------------------

INSERT INTO LoiViPham (MaLoiViPham, LoaiPhuongTien, TenLoiViPham, MucPhatToiThieu, MucPhatToiDa, MucDiemTru)
VALUES
('LVPXM01', 'Xe may', 'Khong chap hanh hieu lenh den tin hieu giao thong', 4000000, 6000000, 6),
('LVPXM02', 'Xe may', 'Chay qua toc do tren 20km/h', 6000000, 8000000, 6),
('LVPXM03', 'Xe may', 'Di vao duong cao toc', 4000000, 6000000, 10),
('LVPXM04', 'Xe may', 'Di nguoc chieu duong mot chieu', 4000000, 6000000, 6),
('LVPXM05', 'Xe may', 'Lang lach, danh vong', 8000000, 10000000, 10),
('LVPXM06', 'Xe may', 'Gay tai nan roi bo tro', 8000000, 10000000, 10),
('LVPXM07', 'Xe may', 'Khong co BLX', 8000000, 10000000, 0),
('LVPOT01', 'O to', 'Dung dien thoai khi lai xe', 4000000, 6000000, 2),
('LVPOT02', 'O to', 'Khong nhuong duong khi ra duong chinh', 4000000, 6000000, 6),
('LVPOT03', 'O to', 'Chuyen huong khong nhuong duong cho nguoi di bo', 4000000, 6000000, 6),
('LVPOT04', 'O to', 'Khong chap hanh hieu lenh den tin hieu giao thong', 18000000, 20000000, 6),
('LVPOT05', 'O to', 'Di nguoc chieu duong mot chieu', 18000000, 20000000, 6),
('LVPOT06', 'O to', 'Khong chap hanh hieu lenh canh sat giao thong', 18000000, 20000000, 6),
('LVPOT07', 'O to', 'Van chuyen hang hoa khong dam bao an toan', 18000000, 22000000, 6),
('LVPOT08', 'O to', 'Di vao duong cao toc khong dung quy dinh', 12000000, 14000000, 6),
('LVPOT09', 'O to', 'Dung xe sai quy dinh tren duong cao toc', 12000000, 14000000, 6),
('LVPOT10', 'O to', 'Chay qua toc do tren 35km/h', 12000000, 14000000, 6),
('LVPOT11', 'O to', 'Mo cua xe khong an toan gay tai nan', 14000000, 16000000, 10),
('LVPOT12', 'O to', 'Chay xe lang lach, danh vong', 40000000, 50000000, 10),
('LVPOT14', 'O to', 'Bien so khong dung quy dinh', 20000000, 26000000, 10),
('LVPOT15', 'O to', 'Di nguoc chieu tren duong cao toc', 30000000, 40000000, 10),
('LVPOT16', 'O to', 'Lui xe tren duong cao toc', 30000000, 40000000, 10),
('LVPOT17', 'O to', 'Quay dau xe tren duong cao toc', 30000000, 40000000, 10),
('LVPOT18', 'O to', 'Khong co BLX', 50000000, 60000000, 0);

-----------------------------------------------------------------------------------------------------------

INSERT INTO DonVi (MaDonVi, TenDonVi) VALUES
-- Cac quan noi thanh
('QBD', N'Canh sat giao thong quan Ba Dinh'),
('QHK', N'Canh sat giao thong quan Hoan Kiem'),
('QHBT', N'Canh sat giao thong quan Hai Ba Trung'),
('QDD', N'Canh sat giao thong quan Dong Da'),
('QTH', N'Canh sat giao thong quan Tay Ho'),
('QCG', N'Canh sat giao thong quan Cau Giay'),
('QTX', N'Canh sat giao thong quan Thanh Xuan'),
('QHM', N'Canh sat giao thong quan Hoang Mai'),
('QLB', N'Canh sat giao thong quan Long Bien'),
('QHD', N'Canh sat giao thong quan Ha Dong');

---------------------------------------------------------------------------------------------------------

INSERT INTO LucLuongChucNang (SoHieu, HoVaTen, ChucVu, MaDonVi) VALUES
-- Đội CSGT quận Ba Đình
('BD01', N'Nguyen Van An', N'Trung ta', 'QBD'),
('BD02', N'Tran Thi Binh', N'Thieu ta', 'QBD'),
('BD03', N'Le Van Cuong', N'Dai uy', 'QBD'),

-- Đội CSGT quận Hoàn Kiếm
('HK01', N'Pham Van Dung', N'Trung ta', 'QHK'),
('HK02', N'Hoang Thi Lan', N'Thieu ta', 'QHK'),

-- Đội CSGT quận Hai Bà Trưng
('HBT01', N'Vu Van Minh', N'Thieu ta', 'QHBT'),
('HBT02', N'Dang Thi Ngoc', N'Dai uy', 'QHBT'),

-- Đội CSGT quận Đống Đa
('DD01', N'Bui Van Quan', N'Thieu ta', 'QDD'),
('DD02', N'Do Thi Huong', N'Dai uy', 'QDD'),

-- Đội CSGT quận Tây Hồ
('TH01', N'Nong Van Son', N'Thieu ta', 'QTH'),
('TH02', N'Ly Thi Mai', N'Thuong uy', 'QTH'),

-- Đội CSGT quận Cầu Giấy
('CG01', N'Trinh Van Hai', N'Thieu ta', 'QCG'),
('CG02', N'Phan Thi Hong', N'Dai uy', 'QCG'),

-- Đội CSGT quận Thanh Xuân
('TX01', N'Hoang Van Tung', N'Thieu ta', 'QTX'),
('TX02', N'Vu Thi Ha', N'Thuong uy', 'QTX'),

-- Đội CSGT quận Hoàng Mai
('HM01', N'Nguyen Van Tuan', N'Thieu ta', 'QHM'),
('HM02', N'Tran Thi Hue', N'Dai uy', 'QHM'),

-- Đội CSGT quận Long Biên
('LB01', N'Vu Viet Long', N'Thieu ta', 'QLB'),
('LB02', N'Pham Thi Nga', N'Thuong uy', 'QLB'),

-- Doi CSGT quan Ha Dong
('HD01', N'Nguyen Huu Dung', N'Thieu ta', 'QHD'),
('HD02', N'Tran Thanh Hai', N'Thuong uy', 'QHD');

---------------------------------------------------------------------------------------------------

INSERT INTO BienBanViPham (MaBienBan, BienKiemSoat, MaBLX, SoHieu, ThoiGianViPham, DiaDiemViPham, TrangThai, TongTienPhat, TongDiemPhat, NgayNopPhat) 
VALUES
('BB20250001', '29A1-0001', 'BLXHN0001', 'DD01', '2025-01-01 08:15:00.000', 'Nga tu Lang Ha - Thai Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250002', '29A2-0001', 'BLXHN0002', 'BD01', '2025-01-02 14:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250003', '29B1-0002', 'BLXHN0003', 'CG01', '2025-01-03 09:45:00.000', 'Nga tu Tran Duy Hung - Pham Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250004', '29B2-0002', 'BLXHN0004', 'DD02', '2025-01-04 16:20:00.000', 'Duong Lang, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250005', '29C1-0003', 'BLXHN0005', 'HM01', '2025-01-05 07:30:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250006', '29C2-0003', 'BLXHN0006', 'TX01', '2025-01-06 13:15:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250007', '29D1-0004', 'BLXHN0007', 'HBT01', '2025-01-07 18:00:00.000', 'Duong Tran Khat Chan, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250008', '29D2-0004', 'BLXHN0008', 'BD02', '2025-01-08 10:45:00.000', 'Duong Le Duan, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250009', '29E1-0005', 'BLXHN0009', 'HBT02', '2025-01-09 08:30:00.000', 'Duong Ba Trieu, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250010', '29E2-0005', 'BLXHN0010', 'BD03', '2025-01-10 15:20:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250011', '29F1-0006', 'BLXHN0011', 'CG02', '2025-01-11 07:45:00.000', 'Duong Xuan Thuy, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250012', '29F2-0006', 'BLXHN0012', 'CG01', '2025-01-12 12:30:00.000', 'Duong Tran Duy Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250013', '29G1-0007', 'BLXHN0013', 'CG02', '2025-01-13 17:15:00.000', 'Duong Hoang Quoc Viet, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250014', '29G2-0007', 'BLXHN0014', 'BD01', '2025-01-14 09:20:00.000', 'Duong Pham Van Dong, Q.Bac Tu Liem', 'Chuaxuly', 0, 0, NULL),
('BB20250015', '29H1-0008', 'BLXHN0015', 'HD01', '2025-01-15 14:10:00.000', 'Duong Tran Phu, Q.Ha Dong', 'Chuaxuly', 0, 0, NULL),
('BB20250016', '29H2-0008', 'BLXHN0016', 'TX02', '2025-01-16 08:45:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250017', '29K1-0009', 'BLXHN0017', 'TX01', '2025-01-17 13:30:00.000', 'Duong Le Van Luong, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250018', '29K2-0009', 'BLXHN0018', 'HD02', '2025-01-18 18:20:00.000', 'Duong To Hieu, Q.Ha Dong', 'Chuaxuly', 0, 0, NULL),
('BB20250019', '29L1-0010', 'BLXHN0019', 'TX02', '2025-01-19 10:15:00.000', 'Duong Nguyen Xien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250020', '29L2-0010', 'BLXHN0020', 'TX01', '2025-01-20 15:45:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250021', '30A1-0021', 'BLXHN0021', 'DD01', '2025-02-01 08:30:00.000', 'Duong Truong Chinh, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250022', '30B1-0022', 'BLXHN0022', 'DD02', '2025-02-02 12:15:00.000', 'Duong Xa Dan, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250023', '30C1-0023', 'BLXHN0023', 'HK01', '2025-02-03 17:00:00.000', 'Duong Le Duan, Q.Hoan Kiem', 'Chuaxuly', 0, 0, NULL),
('BB20250024', '30D1-0024', 'BLXHN0024', 'HK02', '2025-02-04 09:45:00.000', 'Duong Tran Hung Dao, Q.Hoan Kiem', 'Chuaxuly', 0, 0, NULL),
('BB20250025', '30E1-0025', 'BLXHN0025', 'HBT01', '2025-02-05 14:30:00.000', 'Duong Ba Trieu, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250026', '30F1-0026', 'BLXHN0026', 'HBT02', '2025-02-06 08:15:00.000', 'Duong Tran Khat Chan, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250027', '30G1-0027', 'BLXHN0027', 'HBT01', '2025-02-07 13:00:00.000', 'Duong Minh Khai, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250028', '30H1-0028', 'BLXHN0028', 'HM02', '2025-02-08 17:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250029', '30K1-0029', 'BLXHN0029', 'HM01', '2025-02-09 10:30:00.000', 'Duong Tam Trinh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250030', '30L1-0030', 'BLXHN0030', 'HM02', '2025-02-10 15:15:00.000', 'Duong Nguyen Van Linh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250031', '30M1-0031', 'BLXHN0031', 'DD01', '2025-02-11 08:00:00.000', 'Duong Lang Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250032', '30N1-0032', 'BLXHN0032', 'BD02', '2025-02-12 12:45:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250033', '30P1-0033', 'BLXHN0033', 'BD03', '2025-02-13 17:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250034', '30Q1-0034', 'BLXHN0034', 'BD01', '2025-02-14 09:15:00.000', 'Duong Lieu Giai, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250035', '30R1-0035', 'BLXHN0035', 'CG01', '2025-02-15 14:00:00.000', 'Duong Tran Duy Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250036', '30S1-0036', 'BLXHN0036', 'CG02', '2025-02-16 18:45:00.000', 'Duong Pham Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250037', '30T1-0037', 'BLXHN0037', 'TX01', '2025-02-17 11:30:00.000', 'Duong Le Van Luong, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250038', '30U1-0038', 'BLXHN0038', 'TX02', '2025-02-18 16:15:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250039', '30V1-0039', 'BLXHN0039', 'TX01', '2025-02-19 09:00:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250040', '30X1-0040', 'BLXHN0040', 'HM01', '2025-02-20 13:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250041', '30Y1-0041', 'BLXHN0041', 'HBT01', '2025-02-21 08:30:00.000', 'Duong Ba Trieu, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250042', '30Z1-0042', 'BLXHN0042', 'HBT02', '2025-02-22 12:15:00.000', 'Duong Tran Khat Chan, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250043', '31A1-0043', 'BLXHN0043', 'HBT01', '2025-02-23 17:00:00.000', 'Duong Minh Khai, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250044', '31B1-0044', 'BLXHN0044', 'HM02', '2025-02-24 09:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250045', '31C1-0045', 'BLXHN0045', 'HM01', '2025-02-25 14:30:00.000', 'Duong Tam Trinh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250046', '31D1-0046', 'BLXHN0046', 'HM02', '2025-02-26 08:15:00.000', 'Duong Nguyen Van Linh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250047', '31E1-0047', 'BLXHN0047', 'DD01', '2025-02-27 13:00:00.000', 'Duong Lang Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250048', '31F1-0048', 'BLXHN0048', 'BD02', '2025-02-28 17:45:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250049', '31G1-0049', 'BLXHN0049', 'BD03', '2025-02-01 10:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250050', '31H1-0050', 'BLXHN0050', 'BD01', '2025-02-02 15:15:00.000', 'Duong Lieu Giai, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250051', '32A2-0051', 'BLXHN0051', 'DD01', '2025-02-03 08:00:00.000', 'Duong Lang Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250052', '32B2-0052', 'BLXHN0052', 'BD02', '2025-02-04 12:45:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250053', '32C2-0053', 'BLXHN0053', 'BD03', '2025-02-05 17:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250054', '32D2-0054', 'BLXHN0054', 'BD01', '2025-02-06 09:15:00.000', 'Duong Lieu Giai, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250055', '32E2-0055', 'BLXHN0055', 'CG01', '2025-03-01 14:00:00.000', 'Duong Tran Duy Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250056', '32F2-0056', 'BLXHN0056', 'CG02', '2025-03-02 18:45:00.000', 'Duong Pham Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250057', '32G2-0057', 'BLXHN0057', 'TX01', '2025-03-03 11:30:00.000', 'Duong Le Van Luong, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250058', '32H2-0058', 'BLXHN0058', 'TX02', '2025-03-04 16:15:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250059', '32K2-0059', 'BLXHN0059', 'TX01', '2025-03-05 09:00:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250060', '32L2-0060', 'BLXHN0060', 'HM01', '2025-03-06 13:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250061', '32M2-0061', 'BLXHN0061', 'HBT01', '2025-03-07 08:30:00.000', 'Duong Ba Trieu, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250062', '32N2-0062', 'BLXHN0062', 'HBT02', '2025-03-08 12:15:00.000', 'Duong Tran Khat Chan, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250063', '32P2-0063', 'BLXHN0063', 'HBT01', '2025-03-09 17:00:00.000', 'Duong Minh Khai, Q.Hai Ba Trung', 'Chuaxuly', 0, 0, NULL),
('BB20250064', '32Q2-0064', 'BLXHN0064', 'HM02', '2025-03-10 09:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250065', '32R2-0065', 'BLXHN0065', 'HM01', '2025-03-11 14:30:00.000', 'Duong Tam Trinh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250066', '32S2-0066', 'BLXHN0066', 'HM02', '2025-03-12 08:15:00.000', 'Duong Nguyen Van Linh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250067', '32T2-0067', 'BLXHN0067', 'DD01', '2025-03-13 13:00:00.000', 'Duong Lang Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250068', '32U2-0068', 'BLXHN0068', 'BD02', '2025-03-14 17:45:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250069', '32V2-0069', 'BLXHN0069', 'BD03', '2025-03-15 10:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250070', '32X2-0070', 'BLXHN0070', 'BD01', '2025-03-16 15:15:00.000', 'Duong Lieu Giai, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250071', '32Y2-0071', 'BLXHN0071', 'CG01', '2025-03-17 08:00:00.000', 'Duong Tran Duy Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250072', '29A1-0001', 'BLXHN0001', 'CG02', '2025-03-18 12:45:00.000', 'Duong Pham Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250073', '29B1-0002', 'BLXHN0003', 'TX01', '2025-03-19 17:30:00.000', 'Duong Le Van Luong, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250074', '29C1-0003', 'BLXHN0005', 'TX02', '2025-03-20 09:15:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250075', '29D1-0004', 'BLXHN0007', 'TX01', '2025-03-21 14:00:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250076', '29E1-0005', 'BLXHN0009', 'HM01', '2025-03-22 18:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250077', '29F1-0006', 'BLXHN0011', 'HM02', '2025-03-23 11:30:00.000', 'Duong Tam Trinh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250078', '29G1-0007', 'BLXHN0013', 'HM02', '2025-03-24 16:15:00.000', 'Duong Nguyen Van Linh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250079', '29H1-0008', 'BLXHN0015', 'DD01', '2025-03-25 09:00:00.000', 'Duong Lang Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250080', '29K1-0009', 'BLXHN0017', 'BD02', '2025-03-26 13:45:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250081', '29L1-0010', 'BLXHN0019', 'BD03', '2025-03-27 08:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250082', '30A1-0021', 'BLXHN0021', 'BD01', '2025-03-28 12:15:00.000', 'Duong Lieu Giai, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250083', '30C1-0023', 'BLXHN0023', 'CG01', '2025-03-29 17:00:00.000', 'Duong Tran Duy Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250084', '30E1-0025', 'BLXHN0025', 'CG02', '2025-03-30 09:45:00.000', 'Duong Pham Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250085', '30G1-0027', 'BLXHN0027', 'TX01', '2025-03-31 14:30:00.000', 'Duong Le Van Luong, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250086', '30K1-0029', 'BLXHN0029', 'TX02', '2025-03-01 08:15:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250087', '30M1-0031', 'BLXHN0031', 'TX01', '2025-03-02 13:00:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250088', '30P1-0033', 'BLXHN0033', 'HM01', '2025-03-03 17:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250089', '30R1-0035', 'BLXHN0035', 'HM02', '2025-03-04 10:30:00.000', 'Duong Tam Trinh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250090', '30T1-0037', 'BLXHN0037', 'HM02', '2025-03-05 15:15:00.000', 'Duong Nguyen Van Linh, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250091', '30V1-0039', 'BLXHN0039', 'DD01', '2025-03-06 08:00:00.000', 'Duong Lang Ha, Q.Dong Da', 'Chuaxuly', 0, 0, NULL),
('BB20250092', '30Y1-0041', 'BLXHN0041', 'BD02', '2025-03-07 12:45:00.000', 'Duong Nguyen Chi Thanh, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250093', '31A1-0043', 'BLXHN0043', 'BD03', '2025-03-08 17:30:00.000', 'Duong Kim Ma, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250094', '31C1-0045', 'BLXHN0045', 'BD01', '2025-03-09 09:15:00.000', 'Duong Lieu Giai, Q.Ba Dinh', 'Chuaxuly', 0, 0, NULL),
('BB20250095', '31E1-0047', 'BLXHN0047', 'CG01', '2025-03-10 14:00:00.000', 'Duong Tran Duy Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250096', '31G1-0049', 'BLXHN0049', 'CG02', '2025-03-11 18:45:00.000', 'Duong Pham Hung, Q.Cau Giay', 'Chuaxuly', 0, 0, NULL),
('BB20250097', '32A2-0051', 'BLXHN0051', 'TX01', '2025-03-12 11:30:00.000', 'Duong Le Van Luong, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250098', '32C2-0053', 'BLXHN0053', 'TX02', '2025-03-13 16:15:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250099', '32E2-0055', 'BLXHN0055', 'TX01', '2025-03-14 09:00:00.000', 'Duong Nguyen Trai, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250100', '32G2-0057', 'BLXHN0057', 'HM01', '2025-03-15 13:45:00.000', 'Duong Giai Phong, Q.Hoang Mai', 'Chuaxuly', 0, 0, NULL),
('BB20250101', '33U1-0089', NULL, 'HD02', '2025-03-16 18:20:00.000', 'Duong To Hieu, Q.Ha Dong', 'Chuaxuly', 0, 0, NULL),
('BB20250102', '33V1-0090', NULL, 'TX02', '2025-03-17 10:15:00.000', 'Duong Nguyen Xien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250103', '33X1-0091', NULL, 'TX01', '2025-03-18 15:45:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL),
('BB20250104', '29C1-0003', 'BLXHN0005', 'TX02', '2025-03-19 19:45:00.000', 'Duong Khuat Duy Tien, Q.Thanh Xuan', 'Chuaxuly', 0, 0, NULL);

-------------------------------------------------------------------------------------------------------------------------------------- --------

UPDATE BienBanViPham
SET NgayNopPhat = CASE MaBienBan
    WHEN 'BB20250001' THEN '2025-01-05 08:15:00.000'
    WHEN 'BB20250002' THEN '2025-01-14 14:30:00.000'
    WHEN 'BB20250003' THEN '2025-01-10 09:45:00.000'
    WHEN 'BB20250004' THEN '2025-01-17 16:20:00.000'
    WHEN 'BB20250005' THEN '2025-01-12 07:30:00.000'
    WHEN 'BB20250006' THEN '2025-01-14 13:15:00.000'
    WHEN 'BB20250009' THEN '2025-01-16 08:30:00.000'
    WHEN 'BB20250010' THEN '2025-01-24 15:20:00.000'
    WHEN 'BB20250011' THEN '2025-01-18 07:45:00.000'
    WHEN 'BB20250012' THEN '2025-01-20 12:30:00.000'
    WHEN 'BB20250013' THEN '2025-01-25 17:15:00.000'
    WHEN 'BB20250014' THEN '2025-01-22 09:20:00.000'
    WHEN 'BB20250015' THEN '2025-01-23 14:10:00.000'
    WHEN 'BB20250016' THEN '2025-01-29 08:45:00.000'
    WHEN 'BB20250017' THEN '2025-01-25 13:30:00.000'
    WHEN 'BB20250018' THEN '2025-01-26 18:20:00.000'
    WHEN 'BB20250019' THEN '2025-02-03 10:15:00.000'
    WHEN 'BB20250020' THEN '2025-01-28 15:45:00.000'
    WHEN 'BB20250021' THEN '2025-02-08 08:30:00.000'
    WHEN 'BB20250022' THEN '2025-02-14 12:15:00.000'
    WHEN 'BB20250023' THEN '2025-02-10 17:00:00.000'
    WHEN 'BB20250024' THEN '2025-02-12 09:45:00.000'
    WHEN 'BB20250025' THEN '2025-02-18 14:30:00.000'
    WHEN 'BB20250026' THEN '2025-02-14 08:15:00.000'
    WHEN 'BB20250027' THEN '2025-02-15 13:00:00.000'
    WHEN 'BB20250028' THEN '2025-02-19 17:45:00.000'
    WHEN 'BB20250029' THEN '2025-02-17 10:30:00.000'
    WHEN 'BB20250038' THEN '2025-02-26 16:15:00.000'
    WHEN 'BB20250039' THEN '2025-02-27 09:00:00.000'
    WHEN 'BB20250040' THEN '2025-03-07 13:45:00.000'
    WHEN 'BB20250041' THEN '2025-03-01 08:30:00.000'
    WHEN 'BB20250042' THEN '2025-03-02 12:15:00.000'
    WHEN 'BB20250043' THEN '2025-03-07 17:00:00.000'
    WHEN 'BB20250044' THEN '2025-03-04 09:45:00.000'
    WHEN 'BB20250045' THEN '2025-03-05 14:30:00.000'
    WHEN 'BB20250046' THEN '2025-03-09 08:15:00.000'
    WHEN 'BB20250047' THEN '2025-03-07 13:00:00.000'
    WHEN 'BB20250048' THEN '2025-03-08 17:45:00.000'
    WHEN 'BB20250049' THEN '2025-02-14 10:30:00.000'
    WHEN 'BB20250050' THEN '2025-02-10 15:15:00.000'
    WHEN 'BB20250051' THEN '2025-02-11 08:00:00.000'
    WHEN 'BB20250052' THEN '2025-02-18 12:45:00.000'
    WHEN 'BB20250053' THEN '2025-02-13 17:30:00.000'
    WHEN 'BB20250054' THEN '2025-02-14 09:15:00.000'
    WHEN 'BB20250055' THEN '2025-03-13 14:00:00.000'
    WHEN 'BB20250056' THEN '2025-03-10 18:45:00.000'
    WHEN 'BB20250057' THEN '2025-03-11 11:30:00.000'
    WHEN 'BB20250058' THEN '2025-03-17 16:15:00.000'
    WHEN 'BB20250059' THEN '2025-03-13 09:00:00.000'
    WHEN 'BB20250060' THEN '2025-03-14 13:45:00.000'
    WHEN 'BB20250061' THEN '2025-03-18 08:30:00.000'
    WHEN 'BB20250062' THEN '2025-03-16 12:15:00.000'
    WHEN 'BB20250063' THEN '2025-03-17 17:00:00.000'
    WHEN 'BB20250064' THEN '2025-03-24 09:45:00.000'
    WHEN 'BB20250065' THEN '2025-03-19 14:30:00.000'
    WHEN 'BB20250066' THEN '2025-03-20 08:15:00.000'
    WHEN 'BB20250067' THEN '2025-03-25 13:00:00.000'
    WHEN 'BB20250068' THEN '2025-03-22 17:45:00.000'
    WHEN 'BB20250069' THEN '2025-03-23 10:30:00.000'
    WHEN 'BB20250070' THEN '2025-03-31 15:15:00.000'
    WHEN 'BB20250071' THEN '2025-03-25 08:00:00.000'
    WHEN 'BB20250072' THEN '2025-03-26 12:45:00.000'
    WHEN 'BB20250073' THEN '2025-04-01 17:30:00.000'
    WHEN 'BB20250074' THEN '2025-03-28 09:15:00.000'
    WHEN 'BB20250075' THEN '2025-03-29 14:00:00.000'
    WHEN 'BB20250076' THEN '2025-04-03 18:45:00.000'
    WHEN 'BB20250077' THEN '2025-03-31 11:30:00.000'
    WHEN 'BB20250078' THEN '2025-04-01 16:15:00.000'
    WHEN 'BB20250079' THEN '2025-04-05 09:00:00.000'
    WHEN 'BB20250080' THEN '2025-04-03 13:45:00.000'
    WHEN 'BB20250081' THEN '2025-04-04 08:30:00.000'
    WHEN 'BB20250082' THEN '2025-04-11 12:15:00.000'
    WHEN 'BB20250083' THEN '2025-04-06 17:00:00.000'
    WHEN 'BB20250084' THEN '2025-04-07 09:45:00.000'
    WHEN 'BB20250085' THEN '2025-04-13 14:30:00.000'
    WHEN 'BB20250086' THEN '2025-03-09 08:15:00.000'
    WHEN 'BB20250087' THEN '2025-03-10 13:00:00.000'
    WHEN 'BB20250088' THEN '2025-03-15 17:45:00.000'
    WHEN 'BB20250089' THEN '2025-03-12 10:30:00.000'
    WHEN 'BB20250101' THEN '2025-03-24 18:20:00.000'
    WHEN 'BB20250102' THEN '2025-03-25 10:15:00.000'
    WHEN 'BB20250103' THEN '2025-04-01 15:45:00.000'
    WHEN 'BB20250104' THEN '2025-03-27 19:45:00.000'
END
WHERE MaBienBan IN (
    'BB20250001', 'BB20250002', 'BB20250003', 'BB20250004', 'BB20250005',
    'BB20250006', 'BB20250009', 'BB20250010', 'BB20250011', 'BB20250012',
    'BB20250013', 'BB20250014', 'BB20250015', 'BB20250016', 'BB20250017',
    'BB20250018', 'BB20250019', 'BB20250020', 'BB20250021', 'BB20250022',
    'BB20250023', 'BB20250024', 'BB20250025', 'BB20250026', 'BB20250027',
    'BB20250028', 'BB20250029', 'BB20250038', 'BB20250039', 'BB20250040',
    'BB20250041', 'BB20250042', 'BB20250043', 'BB20250044', 'BB20250045',
    'BB20250046', 'BB20250047', 'BB20250048', 'BB20250049', 'BB20250050',
    'BB20250051', 'BB20250052', 'BB20250053', 'BB20250054', 'BB20250055',
    'BB20250056', 'BB20250057', 'BB20250058', 'BB20250059', 'BB20250060',
    'BB20250061', 'BB20250062', 'BB20250063', 'BB20250064', 'BB20250065',
    'BB20250066', 'BB20250067', 'BB20250068', 'BB20250069', 'BB20250070',
    'BB20250071', 'BB20250072', 'BB20250073', 'BB20250074', 'BB20250075',
    'BB20250076', 'BB20250077', 'BB20250078', 'BB20250079', 'BB20250080',
    'BB20250081', 'BB20250082', 'BB20250083', 'BB20250084', 'BB20250085',
    'BB20250086', 'BB20250087', 'BB20250088', 'BB20250089', 'BB20250101',
    'BB20250102', 'BB20250103', 'BB20250104'
);

--===============================================================================================================================================

INSERT INTO CTBienBanViPham (MaChiTiet, MaBienBan, MaLoiViPham, MucTienPhat)
VALUES
('CTBB00001', 'BB20250001', 'LVPXM01', 5000000),
('CTBB00002', 'BB20250001', 'LVPXM03', 5000000),
('CTBB00003', 'BB20250002', 'LVPOT04', 19000000),
('CTBB00004', 'BB20250003', 'LVPXM02', 7000000),
('CTBB00005', 'BB20250004', 'LVPOT04', 19000000),
('CTBB00006', 'BB20250004', 'LVPOT09', 13000000),
('CTBB00007', 'BB20250005', 'LVPXM01', 5000000),
('CTBB00008', 'BB20250005', 'LVPXM06', 9000000),
('CTBB00009', 'BB20250006', 'LVPOT01', 5000000),
('CTBB00010', 'BB20250007', 'LVPXM01', 4500000),
('CTBB00011', 'BB20250007', 'LVPXM06', 9000000),
('CTBB00012', 'BB20250008', 'LVPOT04', 18500000),
('CTBB00013', 'BB20250009', 'LVPXM06', 9000000),
('CTBB00014', 'BB20250010', 'LVPOT04', 20000000),
('CTBB00015', 'BB20250010', 'LVPOT10', 13000000),
('CTBB00016', 'BB20250011', 'LVPXM01', 5000000),
('CTBB00017', 'BB20250012', 'LVPOT02', 5000000),
('CTBB00018', 'BB20250013', 'LVPXM02', 7000000),
('CTBB00019', 'BB20250014', 'LVPOT06', 19000000),
('CTBB00020', 'BB20250015', 'LVPXM03', 5000000),
('CTBB00021', 'BB20250016', 'LVPOT08', 13000000),
('CTBB00022', 'BB20250017', 'LVPXM01', 5000000),
('CTBB00023', 'BB20250018', 'LVPOT11', 15000000),
('CTBB00024', 'BB20250019', 'LVPXM05', 9000000),
('CTBB00025', 'BB20250020', 'LVPOT12', 45000000),
('CTBB00026', 'BB20250021', 'LVPXM01', 5000000),
('CTBB00027', 'BB20250022', 'LVPXM06', 9000000),
('CTBB00028', 'BB20250023', 'LVPXM01', 5000000),
('CTBB00029', 'BB20250024', 'LVPXM05', 8500000),
('CTBB00030', 'BB20250025', 'LVPXM01', 5000000),
('CTBB00031', 'BB20250026', 'LVPXM01', 6000000),
('CTBB00032', 'BB20250027', 'LVPXM02', 7000000),
('CTBB00033', 'BB20250028', 'LVPXM01', 5000000),
('CTBB00034', 'BB20250029', 'LVPXM03', 5000000),
('CTBB00035', 'BB20250030', 'LVPXM01', 5500000),
('CTBB00036', 'BB20250031', 'LVPXM04', 6000000),
('CTBB00037', 'BB20250032', 'LVPXM01', 4500000),
('CTBB00038', 'BB20250033', 'LVPXM05', 9000000),
('CTBB00039', 'BB20250034', 'LVPXM01', 5600000),
('CTBB00040', 'BB20250035', 'LVPXM06', 9000000),
('CTBB00041', 'BB20250036', 'LVPXM01', 5000000),
('CTBB00042', 'BB20250037', 'LVPXM06', 9000000),
('CTBB00043', 'BB20250038', 'LVPXM01', 5100000),
('CTBB00044', 'BB20250039', 'LVPXM01', 5500000),
('CTBB00045', 'BB20250040', 'LVPXM02', 6500000),
('CTBB00046', 'BB20250041', 'LVPXM01', 5000000),
('CTBB00047', 'BB20250042', 'LVPXM03', 4500000),
('CTBB00048', 'BB20250043', 'LVPXM01', 5000000),
('CTBB00049', 'BB20250044', 'LVPXM04', 5500000),
('CTBB00050', 'BB20250045', 'LVPXM01', 5000000),
('CTBB00051', 'BB20250046', 'LVPXM05', 8500000),
('CTBB00052', 'BB20250047', 'LVPXM01', 5000000),
('CTBB00053', 'BB20250048', 'LVPXM06', 8500000),
('CTBB00054', 'BB20250049', 'LVPXM01', 5000000),
('CTBB00055', 'BB20250050', 'LVPXM05', 9000000),
('CTBB00056', 'BB20250051', 'LVPOT11', 15000000),
('CTBB00057', 'BB20250052', 'LVPOT12', 45000000),
('CTBB00058', 'BB20250053', 'LVPOT04', 19000000),
('CTBB00059', 'BB20250054', 'LVPOT15', 35000000),
('CTBB00060', 'BB20250055', 'LVPOT16', 35000000),
('CTBB00061', 'BB20250056', 'LVPOT17', 35000000),
('CTBB00062', 'BB20250057', 'LVPOT17', 31000000),
('CTBB00063', 'BB20250058', 'LVPOT01', 5000000),
('CTBB00064', 'BB20250059', 'LVPOT02', 5000000),
('CTBB00065', 'BB20250060', 'LVPOT03', 5000000),
('CTBB00066', 'BB20250061', 'LVPOT04', 19000000),
('CTBB00067', 'BB20250062', 'LVPOT05', 19000000),
('CTBB00068', 'BB20250063', 'LVPOT06', 19000000),
('CTBB00069', 'BB20250064', 'LVPOT04', 20000000),
('CTBB00070', 'BB20250065', 'LVPOT08', 13000000),
('CTBB00071', 'BB20250066', 'LVPOT09', 13000000),
('CTBB00072', 'BB20250067', 'LVPOT10', 13000000),
('CTBB00073', 'BB20250068', 'LVPOT11', 15000000),
('CTBB00074', 'BB20250069', 'LVPOT12', 45000000),
('CTBB00075', 'BB20250070', 'LVPOT14', 23000000),
('CTBB00076', 'BB20250071', 'LVPOT15', 35000000),
('CTBB00077', 'BB20250072', 'LVPXM01', 5000000),
('CTBB00078', 'BB20250073', 'LVPXM02', 7000000),
('CTBB00079', 'BB20250074', 'LVPXM03', 5000000),
('CTBB00080', 'BB20250075', 'LVPXM04', 5000000),
('CTBB00081', 'BB20250076', 'LVPXM05', 9000000),
('CTBB00082', 'BB20250077', 'LVPXM06', 9000000),
('CTBB00083', 'BB20250078', 'LVPXM05', 9000000),
('CTBB00084', 'BB20250079', 'LVPXM01', 5000000),
('CTBB00085', 'BB20250080', 'LVPXM02', 7000000),
('CTBB00086', 'BB20250081', 'LVPXM03', 5000000),
('CTBB00087', 'BB20250082', 'LVPXM04', 5000000),
('CTBB00088', 'BB20250083', 'LVPXM05', 9000000),
('CTBB00089', 'BB20250084', 'LVPXM06', 9000000),
('CTBB00090', 'BB20250085', 'LVPXM05', 9000000),
('CTBB00091', 'BB20250086', 'LVPXM01', 5000000),
('CTBB00092', 'BB20250087', 'LVPXM02', 7000000),
('CTBB00093', 'BB20250088', 'LVPXM03', 5000000),
('CTBB00094', 'BB20250089', 'LVPXM04', 5000000),
('CTBB00095', 'BB20250090', 'LVPXM05', 9000000),
('CTBB00096', 'BB20250091', 'LVPXM06', 9000000),
('CTBB00097', 'BB20250092', 'LVPXM05', 9000000),
('CTBB00098', 'BB20250093', 'LVPXM01', 5000000),
('CTBB00099', 'BB20250094', 'LVPXM02', 7000000),
('CTBB00100', 'BB20250095', 'LVPXM03', 5000000),
('CTBB00101', 'BB20250096', 'LVPXM04', 5000000),
('CTBB00102', 'BB20250097', 'LVPOT01', 5000000),
('CTBB00103', 'BB20250098', 'LVPOT02', 5000000),
('CTBB00104', 'BB20250099', 'LVPOT03', 5000000),
('CTBB00105', 'BB20250100', 'LVPOT04', 19000000),
('CTBB00106', 'BB20250101', 'LVPOT18', 55000000),
('CTBB00107', 'BB20250102', 'LVPOT18', 55000000),
('CTBB00108', 'BB20250103', 'LVPOT18', 55000000),
('CTBB00109', 'BB20250104', 'LVPXM02', 7000000),
('CTBB00110', 'BB20250104', 'LVPXM01', 4000000),
('CTBB00111', 'BB20250103', 'LVPOT02', 5000000),
('CTBB00112', 'BB20250103', 'LVPOT04', 19000000),
('CTBB00113', 'BB20250010', 'LVPOT01', 4000000),
('CTBB00114', 'BB20250101', 'LVPOT17', 35000000),
('CTBB00115', 'BB20250102', 'LVPOT02', 5500000),
('CTBB00116', 'BB20250103', 'LVPOT01', 5500000),
('CTBB00117', 'BB20250072', 'LVPXM07', 9000000),
('CTBB00118', 'BB20250074', 'LVPXM07', 9000000),
('CTBB00119', 'BB20250104', 'LVPXM07', 9000000),
('CTBB00120', 'BB20250075', 'LVPXM07', 9000000);

-------------------------------------------------------------------------------------------------------------------------------------------

INSERT INTO DonKhieuNai (MaDonKhieuNai, SoCCCD, HoVaTen, ThoiGianKhieuNai, NoiDung, ThoiGianXuLy, TrangThai, MaBienBan, SoHieu) VALUES
('DK20250001', '001201000004', N'Pham Thi D', '2025-01-14 14:30:00', N'Xe may bi hong phanh nen khong dung kip den do', '2025-01-19 10:00:00', N'Datuchoi', 'BB20250007', 'HBT01'),
('DK20250002', '001201000004', N'Pham Thi D', '2025-01-15 09:15:00', N'Dang cho nguoi nha di cap cuu nen phai vuot den', NULL, N'ChuaXuLy', 'BB20250008', 'BD02'),
('DK20250003', '001201000020', N'Pham Thi U', '2025-02-17 16:20:00', N'Khong nhin thay bien bao do mua lon', '2025-02-23 11:45:00', N'Datuchoi', 'BB20250030', 'HM02'),
('DK20250004', '001201000021', N'Hoang Van V', '2025-02-18 08:30:00', N'Xin giam muc phat do hoan canh gia dinh kho khan', NULL, N'ChuaXuLy', 'BB20250031', 'DD01'),
('DK20250005', '001201000022', N'Vu Thi X', '2025-02-19 10:45:00', N'Duong bi ngap nuoc phai di len lan khac', NULL, N'ChuaXuLy', 'BB20250032', 'BD02'),
('DK20250006', '001201000023', N'Dang Van Y', '2025-02-20 17:45:00', N'Xe thue nen khong biet ro tinh trang ky thuat', '2025-02-27 14:00:00', N'Datuchoi', 'BB20250033', 'BD03'),
('DK20250007', '001201000024', N'Bui Thi Z', '2025-02-21 09:30:00', N'Bi nguoi khac cat mat nen phai danh vong', NULL, N'ChuaXuLy', 'BB20250034', 'BD01'),
('DK20250008', '001201000025', N'Do Van AA', '2025-02-22 15:20:00', N'Den tin hieu bi mo khong quan sat duoc', NULL, N'ChuaXuLy', 'BB20250035', 'CG01'),
('DK20250009', '001201000026', N'Ngo Thi AB', '2025-02-23 19:10:00', N'Xin xem xet lai do nham bien so xe', '2025-03-01 16:00:00', N'Datuchoi', 'BB20250036', 'CG02'),
('DK20250010', '001201000027', N'Ly Van AC', '2025-02-24 14:45:00', N'Co camera chung minh khong vi pham', NULL, N'ChuaXuLy', 'BB20250037', 'TX01'),
('DK20250011', '001201000027', N'Ly Van AC', '2025-03-13 16:20:00', N'Xe bi hong phanh dot xuat', NULL, N'ChuaXuLy', 'BB20250090', 'HM02'),
('DK20250012', '001201000029', N'Phan Van AE', '2025-03-14 09:50:00', N'Cho nguoi benh di cap cuu', NULL, N'ChuaXuLy', 'BB20250091', 'DD01'),
('DK20250013', '001201000031', N'Ho Van AG', '2025-03-15 13:10:00', N'Khong dong y voi bien ban vi cho rang khong vi pham', '2025-03-23 10:45:00', N'Datuchoi', 'BB20250092', 'BD02'),
('DK20250014', '001201000033', N'Nguyen Van AI', '2025-03-16 18:50:00', N'Xin giam muc phat do vi pham lan dau', NULL, N'ChuaXuLy', 'BB20250093', 'BD03'),
('DK20250015', '001201000035', N'Le Van AK', '2025-03-17 17:30:00', N'Bi benh dot xuat nen khong kiem soat duoc toc do', '2025-03-25 15:15:00', N'Datuchoi', 'BB20250094', 'BD01');



