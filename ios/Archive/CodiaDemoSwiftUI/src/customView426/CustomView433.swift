//
//  CustomView433.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView433: View {
    @State public var text224Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text224Text)
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

struct CustomView433_Previews: PreviewProvider {
    static var previews: some View {
        CustomView433()
    }
}
