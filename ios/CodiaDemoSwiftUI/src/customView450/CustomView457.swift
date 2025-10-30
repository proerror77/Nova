//
//  CustomView457.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView457: View {
    @State public var text230Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text230Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 14))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 44, height: 20, alignment: .topLeading)
    }
}

struct CustomView457_Previews: PreviewProvider {
    static var previews: some View {
        CustomView457()
    }
}
