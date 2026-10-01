import Foundation

@objc(HibernalHelperProtocol)
protocol HibernalHelperProtocol {
    func executeHibernateScript(at path: String, with reply: @escaping (Bool, String?) -> Void)
    func setACSleepTimer(minutes: Int, with reply: @escaping (Bool, String?) -> Void)
}