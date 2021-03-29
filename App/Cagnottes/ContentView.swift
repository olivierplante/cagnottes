//
//  ContentView.swift
//  Cagnottes
//
//  Created by Olivier Plante on 2021-03-27.
//

import SwiftUI
import Combine
import Web3
import Web3ContractABI

struct ContentView: View {
    @ObservedObject private var viewModel = ViewModel()
    var body: some View {
        VStack {
            TextField("address", text: $viewModel.address)
                .padding()
            Text(viewModel.balance)
                .padding()
            Button("Create Cagnotte") {
                viewModel.createTap.send()
            }
            TextField("cagnotte id", text: $viewModel.cagnotteId)
                .padding()
            Button("Contribute") {
                viewModel.contributeTap.send()
            }
            Button("Collect") {
                viewModel.collectTap.send()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

class ViewModel: ObservableObject {
    
    enum Error: Swift.Error {
        case fuck
    }
    
    private var cancellableBag = Set<AnyCancellable>()
    private let ethereum = Ethereum()
    
    //Input
    @Published var address = ""
    @Published var cagnotteId = ""
    var createTap = PassthroughSubject<Void, Never>()
    var contributeTap = PassthroughSubject<Void, Never>()
    var collectTap = PassthroughSubject<Void, Never>()
    
    //Output
    @Published var balance = ""
    
    init() {
        $address
            .flatMap { address in
                self.ethereum.getBalance(address: address)
            }
            .receive(on: RunLoop.main)
            .assign(to: \.balance, on: self)
            .store(in: &cancellableBag)
        
        createTap
            .flatMap { _ in
                self.ethereum.createCagnotte()
            }
            .sink { data in
                print(data)
            }
            .store(in: &cancellableBag)
        
        contributeTap
            .flatMap { _ -> AnyPublisher<EthereumData?, Never> in
                guard let cagnotteId = UInt(self.cagnotteId) else { return Just(nil).eraseToAnyPublisher() }
                return self.ethereum.contribute(cagnoteId: cagnotteId)
            }
            .sink { data in
                print(data)
            }
            .store(in: &cancellableBag)
        
        collectTap
            .flatMap { _ -> AnyPublisher<EthereumData?, Never> in
                guard let cagnotteId = UInt(self.cagnotteId) else { return Just(nil).eraseToAnyPublisher() }
                return self.ethereum.collect(cagnoteId: cagnotteId)
            }
            .sink { data in
                print(data)
            }
            .store(in: &cancellableBag)
    }
}

struct Ethereum {
//    let web3 = Web3(rpcURL: "https://mainnet.infura.io/v3/ee6da4ef84af4efba720326874a52f21")
    let web3 = Web3(rpcURL: "http://127.0.0.1:7545")
    var contract: CagnotteContract { web3.eth.Contract(type: CagnotteContract.self, address: try! EthereumAddress(hex: "0x8de210EdAf64bFE85d4CAbe7551A8a6368b76796", eip55: false)) }
    let privateKey = try! EthereumPrivateKey(hexPrivateKey: "cf098ffb02d2f4536f6069960cf96030979725d71c8ab2d22f16362c146c3e20")
    
    func getBalance(address: String) -> Future<String, Never> {
        return Future { promise in
            try? web3.eth.getBalance(address: EthereumAddress(hex: address, eip55: true), block: .latest) { result in
                let wei = try? BigUInt("\(pow(10, 18))")
                let quantity = result.result?.quantity ?? 0
                let eth = quantity.quotientAndRemainder(dividingBy: wei ?? 1)
                promise(.success("\(eth.quotient).\(eth.remainder)"))
            }
        }
    }
    
    func createCagnotte() -> AnyPublisher<EthereumData?, Never> {
        let to = try! EthereumAddress(hex: "0x770047A8Cb7Ed7dA60f99b6773Cc2553fDDc34e2", eip55: false)
        return processSignedTransaction { nonce in
            contract.createCagnotte(address: to)
                .createTransaction(nonce: nonce,
                                   from: privateKey.address,
                                   value: 0,
                                   gas: 500000,
                                   gasPrice: 1)
        }
    }
    
    func contribute(cagnoteId: UInt) -> AnyPublisher<EthereumData?, Never> {
        return processSignedTransaction { nonce in
            contract.contribute(id: cagnoteId)
                .createTransaction(nonce: nonce,
                                   from: privateKey.address,
                                   value: EthereumQuantity(quantity: 1.eth),
                                   gas: 500000,
                                   gasPrice: 1)
        }
    }
    
    func collect(cagnoteId: UInt) -> AnyPublisher<EthereumData?, Never> {
        return processSignedTransaction { nonce in
            contract.collect(id: cagnoteId)
                .createTransaction(nonce: nonce,
                                   from: privateKey.address,
                                   value: 0,
                                   gas: 500000,
                                   gasPrice: 1)
        }
    }
    
    private func processSignedTransaction(_ closure: @escaping (EthereumQuantity?) -> (EthereumTransaction?)) -> AnyPublisher<EthereumData?, Never> {
        return getTransactionCount()
            .compactMap { nonce in
                closure(nonce)
            }
            .compactMap{ transaction in
                try? transaction.sign(with: privateKey, chainId: 5777)
            }
            .flatMap { tx in
                sendRawTransaction(transaction: tx)
            }
            .eraseToAnyPublisher()
    }
    
    private func getTransactionCount() -> Future<EthereumQuantity, Never> {
        return Future { promise in
            try? web3.eth.getTransactionCount(address: privateKey.address, block: .latest, response: { response in
                promise(.success(response.result ?? 0))
            })
        }
    }
    
    private func sendRawTransaction(transaction: EthereumSignedTransaction) -> Future<EthereumData?, Never> {
        Future { promise in
            web3.eth.sendRawTransaction(transaction: transaction) { result in
                promise(.success(result.result))
            }
        }
    }
}

class CagnotteContract: StaticContract {
    var address: EthereumAddress?
    var eth: Web3.Eth
    var events: [SolidityEvent] { [] }
    
    required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
    
    func createCagnotte(address: EthereumAddress) -> SolidityInvocation {
        let inputs = [SolidityFunctionParameter(name: "to", type: .address)]
        let outputs = [SolidityFunctionParameter(name: "_cagnotteId", type: .uint256)]
        let method = SolidityNonPayableFunction(name: "createCagnotte", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(address)
    }
    
    func contribute(id: UInt) -> SolidityInvocation {
        let inputs = [SolidityFunctionParameter(name: "id", type: .uint)]
        let method = SolidityPayableFunction(name: "contribute", inputs: inputs, handler: self)
        return method.invoke(id)
    }
    
    func collect(id: UInt) -> SolidityInvocation {
        let inputs = [SolidityFunctionParameter(name: "id", type: .uint)]
        let method = SolidityPayableFunction(name: "collect", inputs: inputs, handler: self)
        return method.invoke(id)
    }
}
