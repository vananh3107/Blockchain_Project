// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Invoice Settlement DApp
/// @notice Doanh nghiệp phát hành hóa đơn; khách hàng trả theo nhiều đợt bằng ETH.
contract InvoiceSettlement {
    // ---------------------------------------------------------------
    // 1. DỮ LIỆU (state)
    // ---------------------------------------------------------------

    /// Ví doanh nghiệp = ví đã deploy contract. Không đổi được -> immutable.
    address public immutable owner;

    /// Một lần thanh toán (để hiển thị "các khoản đã trả").
    struct Payment {
        address payer;     // ví đã trả
        uint256 amount;    // số wei của lần trả này
        uint256 timestamp; // thời điểm (giây, theo block)
    }

    /// Một hóa đơn.
    struct Invoice {
        bool exists;          // đã được tạo chưa (dùng để kiểm tra mã trùng)
        address customer;     // ví khách hàng được phép trả
        uint256 totalAmount;  // tổng tiền hóa đơn (wei)
        uint256 paidAmount;   // tổng đã trả (wei)
        bool isPaid;          // đã tất toán chưa
    }

    /// mã hóa đơn => hóa đơn
    mapping(uint256 => Invoice) private invoices;
    /// mã hóa đơn => danh sách các lần trả
    mapping(uint256 => Payment[]) private payments;
    /// danh sách mã hóa đơn để UI liệt kê
    uint256[] private invoiceIds;

    // ---------------------------------------------------------------
    // 2. SỰ KIỆN (event) - nhật ký công khai trên blockchain
    // ---------------------------------------------------------------
    event InvoiceCreated(uint256 indexed invoiceId, address indexed customer, uint256 amount);
    event InvoicePaymentReceived(uint256 indexed invoiceId, address indexed payer, uint256 amount, uint256 remaining);
    event InvoiceSettled(uint256 indexed invoiceId);

    // ---------------------------------------------------------------
    // 3. MODIFIER - ràng buộc quyền
    // ---------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Chi doanh nghiep moi duoc phat hanh hoa don");
        _;
    }

    constructor() {
        owner = msg.sender; // người deploy là doanh nghiệp
    }

    // ---------------------------------------------------------------
    // 4. HÀM GHI (tốn gas)
    // ---------------------------------------------------------------

    /// @notice Doanh nghiệp tạo hóa đơn.
    /// @param invoiceId mã hóa đơn (duy nhất)
    /// @param customer  ví khách hàng
    /// @param amount    số tiền nợ, đơn vị wei (0.3 ETH = 300000000000000000)
    function createInvoice(uint256 invoiceId, address customer, uint256 amount) external onlyOwner {
        require(!invoices[invoiceId].exists, "Ma hoa don da ton tai");
        require(amount > 0, "So tien phai lon hon 0");
        require(customer != address(0), "Dia chi khach hang khong hop le");

        invoices[invoiceId] = Invoice({
            exists: true,
            customer: customer,
            totalAmount: amount,
            paidAmount: 0,
            isPaid: false
        });
        invoiceIds.push(invoiceId);

        emit InvoiceCreated(invoiceId, customer, amount);
    }

    /// @notice Khách hàng trả một phần hoặc toàn bộ nợ. Gửi kèm ETH (payable).
    function payInvoice(uint256 invoiceId) external payable {
        Invoice storage inv = invoices[invoiceId];

        // --- CHECKS: kiểm tra điều kiện ---
        require(inv.exists, "Hoa don khong ton tai");
        require(msg.sender == inv.customer, "Chi vi khach hang cua hoa don moi duoc thanh toan");
        require(!inv.isPaid, "Hoa don da tat toan");
        require(msg.value > 0, "So tien tra phai lon hon 0");

        uint256 remaining = inv.totalAmount - inv.paidAmount;
        require(msg.value <= remaining, "Khong duoc tra vuot so du no");

        // --- EFFECTS: cập nhật trạng thái TRƯỚC khi chuyển tiền ---
        inv.paidAmount += msg.value;
        payments[invoiceId].push(Payment(msg.sender, msg.value, block.timestamp));

        uint256 newRemaining = inv.totalAmount - inv.paidAmount;
        emit InvoicePaymentReceived(invoiceId, msg.sender, msg.value, newRemaining);

        if (newRemaining == 0) {
            inv.isPaid = true; // tất toán
            emit InvoiceSettled(invoiceId);
        }

        // --- INTERACTIONS: chuyển ETH cho doanh nghiệp SAU CÙNG ---
        (bool ok, ) = payable(owner).call{value: msg.value}("");
        require(ok, "Chuyen ETH cho doanh nghiep that bai");
    }

    // ---------------------------------------------------------------
    // 5. HÀM ĐỌC (view - miễn phí gas khi gọi từ bên ngoài)
    // ---------------------------------------------------------------

    /// @notice Số tiền còn nợ (wei).
    function getInvoiceBalance(uint256 invoiceId) public view returns (uint256) {
        Invoice storage inv = invoices[invoiceId];
        require(inv.exists, "Hoa don khong ton tai");
        return inv.totalAmount - inv.paidAmount;
    }

    /// @notice Hóa đơn đã tất toán chưa.
    function isInvoicePaid(uint256 invoiceId) external view returns (bool) {
        require(invoices[invoiceId].exists, "Hoa don khong ton tai");
        return invoices[invoiceId].isPaid;
    }

    /// @notice Thông tin đầy đủ của hóa đơn (phục vụ giao diện).
    function getInvoice(uint256 invoiceId)
        external
        view
        returns (address customer, uint256 totalAmount, uint256 paidAmount, uint256 remaining, bool isPaid)
    {
        Invoice storage inv = invoices[invoiceId];
        require(inv.exists, "Hoa don khong ton tai");
        return (inv.customer, inv.totalAmount, inv.paidAmount, inv.totalAmount - inv.paidAmount, inv.isPaid);
    }

    /// @notice Các lần thanh toán của một hóa đơn.
    function getPayments(uint256 invoiceId) external view returns (Payment[] memory) {
        require(invoices[invoiceId].exists, "Hoa don khong ton tai");
        return payments[invoiceId];
    }

    /// @notice Danh sách mã hóa đơn đã tạo.
    function getInvoiceIds() external view returns (uint256[] memory) {
        return invoiceIds;
    }
}
